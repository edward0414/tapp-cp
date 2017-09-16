class DdahsController < ApplicationController
  protect_from_forgery with: :null_session
  include DdahUpdater
  include Authorizer
  before_action :correct_applicant, only: [:student_pdf, :student_accept]
  before_action :either_cp_admin_instructor, only: [:index, :show, :create, :destroy, :update]
  before_action :cp_admin, only: [:accept, :can_send_contract, :send_contracts, :can_nag_student, :send_nag_student, :can_approve_ddah, :approve_ddah]
  before_action  only: [:pdf, :separate_from_template, :new_template] do
    both_cp_admin_instructor(Ddah)
  end
  before_action only: [:apply_template, :can_finish_ddah, :finish_ddah] do
    both_cp_admin_instructor(Ddah, :ddahs, true)
  end

  def index
    if params[:utorid]
      render json: get_all_ddahs(get_all_ddah_for_utorid(params[:utorid]))
    else
      render json: get_all_ddahs(Ddah.all)
    end
  end

  def show
    if params[:utorid]
      ddahs = id_array(get_all_ddah_for_utorid(params[:utorid]))
      if ddahs.include?(params[:id])
        ddah = Ddah.find(params[:id])
        render json: ddah.format
      else
        render status: 404, json: {status: 404}
      end
    else
      ddah = Ddah.find(params[:id])
      render json: ddah.format
    end
  end

  def create
    offer = Offer.find(params[:offer_id])
    instructor = Instructor.find_by!(utorid: params[:utorid])
    ddah = Ddah.find_by(offer_id: offer[:id])
    if !ddah
      if params[:use_template]
        if template_match_offer(params[:template_id], offer)
          Ddah.create!(
            offer_id: offer[:id],
            template_id: params[:template_id],
            instructor_id: instructor[:id],
          )
        else
          render status: 404, json: {message: "Error: Mismatched Position. Operation Aborted."}
        end
      else
        Ddah.create!(
          offer_id: offer[:id],
          instructor_id: instructor[:id],
          optional: true,
        )
      end
      offer.update_attributes!(ddah_status: "Created")
      render status: 200, json: {message: "A DDAH was successfully created."}
    else
      render status: 404, json: {message: "Error: A DDAH already exists for this offer."}
    end
  end

  def destroy
    ddah = Ddah.find(params[:id])
    ddah.allocations.each do |allocation|
      allocation.destroy!
    end
    ddah.destroy!
  end

  def update
    ddah = Ddah.find(params[:id])
    ddah.update_attributes!(ddah_params)
    if !ddah[:template_id]
      update_form(ddah, params)
      render status: 200, json: {message: "DDAH was updated successfully."}
    else
      render status: 404, json: {message: "Error: This DDAH is currently using a template. You need to either update the template or separate this DDAH from the current template."}
    end
  end

  '''
    Template DDAH (instructor)
  '''
  def apply_template
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      if ddah[:template_id]
        clear_ddah(ddah)
        ddah.update_attributes!(template_id: params[:template_id])
      else
        ddah.update_attributes!(template_id: params[:template_id])
      end
    end
    render status: 200, json: {message: "Batch template apply success."}
  end

  def new_template
    ddah = Ddah.find(params[:ddah_id])
    if !ddah[:template_id]
      offer = Offer.find(ddah[:offer_id])
      position = Position.find(offer[:position_id])
      data = {
        name: params[:name],
        optional: ddah[:optional],
        instructor_id: ddah[:instructor_id],
        tutorial_category: ddah[:tutorial_category],
        department: ddah[:department],
        scaling_learning: ddah[:scaling_learning],
        position_id: position[:id],
      }
      template = Template.create!(data)
      copy_allocations(template, ddah.allocations, :ddah_id, :template_id)
      template.training_ids = ddah.training_ids
      template.category_ids = ddah.category_ids
      render status: 200, json: {message: "A new template was successfully created."}
    else
      render status: 404, json: {message: "Error: A new template cannot be created from a DDAH that is already using a template."}
    end
  end

  def separate_from_template
    ddah = Ddah.find(params[:ddah_id])
    if ddah[:template_id]
      template = Template.find(ddah[:template_id])
      data = {
        optional: template[:optional],
        instructor_id: template[:instructor_id],
        tutorial_category: template[:tutorial_category],
        department: template[:department],
        scaling_learning: template[:scaling_learning],
      }
      ddah.update_attributes!(data)
      copy_allocations(ddah, template.allocations, :template_id, :ddah_id)
      ddah.trainings = template.training_ids
      ddah.categories = template.category_ids
      render status: 200, json: {message: "The DDAH was successfully separated from its template."}
    else
      render status: 404, json: {message: "Error: A DDAH cannot be separated if it does not have a template."}
    end
  end


  '''
    Send Mails (admin)
  '''
  def can_send_ddahs
    check_ddah_status(params[:ddahs], ["Approved"])
  end

  def send_ddahs
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      if ENV['RAILS_ENV'] != 'test'
        link = "#{ENV["domain"]}#{offer[:link]}".sub!("pb", "pb/ddah")
        CpMailer.ddah_email(ddah.format,link).deliver_now!
      end
      offer.update_attributes!(ddah_status: "Pending")
      ddah.update_attributes!(send_date: DateTime.now.to_s)
    end
    render status: 200, json: {message: "You've successfully sent out all the DDAH's."}
  end


  def can_nag_student
    check_ddah_status(params[:ddahs], ["Pending"])
  end

  def send_nag_student
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      if ENV['RAILS_ENV'] != 'test'
        link = "#{ENV["domain"]}#{offer[:link]}".sub!("pb", "pb/ddah")
        CpMailer.ddah_nag_email(ddah.format, link).deliver_now!
      end
      ddah.increment!(:nag_count, 1)
    end
    render json: {message: "You've sent the nag emails."}
  end

  '''
    Set DDAH status to "Ready" (instructor)
  '''
  def can_finish_ddah
    check_ddah_status(params[:ddahs], ["None", "Created"])
  end

  def finish_ddah
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      offer.update_attributes!(ddah_status: "Ready")
      ddah.update_attributes!(supervisor_signature: params[:signature], supervisor_sign_date: DateTime.now.to_date)
    end
    render status: 200, json: {message: "The selected DDAH's have been signed and set to status 'Ready'."}
  end

  '''
    Set DDAH status to "Approved" (admin)
  '''
  def can_approve_ddah
    check_ddah_status(params[:ddahs], ["Ready"])
  end

  def approve_ddah
    params[:ddahs].each do |id|
      ddah = Ddah.find(id)
      offer = Offer.find(ddah[:offer_id])
      offer.update_attributes!(ddah_status: "Approved")
      ddah.update_attributes!(ta_coord_signature: params[:signature], ta_coord_sign_date: DateTime.now.to_date)
    end
    render status: 200, json: {message: "The selected DDAH's have been signed and set to status 'Approved'."}
  end

  def pdf
    ddah = Ddah.find(params[:ddah_id])
    if ddah
      get_ddah_pdf(ddah)
    else
      render status: 404, json: {message: "Error: A DDAH has not been made for this offer."}
    end
  end

  def accept
    ddah = Ddah.find(params[:ddah_id])
    accept_ddah(ddah[:offer_id])
  end

  '''
    Student-Facing
  '''
  def student_pdf
    ddah = Ddah.find_by(offer_id: params[:offer_id])
    if ddah
      get_ddah_pdf(ddah)
    else
      render status: 404, json: {message: "Error: A DDAH has not been made for this offer."}
    end
  end

  def student_accept
    accept_ddah(params[:offer_id], true, params[:signature])
  end

  private
  def get_ddah_pdf(ddah)
    generator = DdahGenerator.new(ddah.format)
    send_data generator.render, filename: "ddah.pdf", disposition: "inline"
  end

  def accept_ddah(offer_id, student = false, signature = nil)
    offer = Offer.find(offer_id)
    if offer[:ddah_status] == "Accepted"
      render status: 404, json: {message: "Error: You have already accepted this DDAH.", status: offer[:ddah_status]}
    else
      ddah = Ddah.find_by(offer_id: offer_id)
      if ddah
        if student
          accept_student_ddah(ddah, offer, signature, DateTime.now.to_date)
        else
          offer.update_attributes!(ddah_status: "Accepted")
          ddah.update_attributes!(student_signature: signature, student_sign_date:  DateTime.now.to_date)
          render status: 200, json: {message: "You have accepted this DDAH.", status: offer[:ddah_status]}
        end
      else
        render status: 404, json: {message: "Error: DDAH not found."}
      end
    end
  end

  def accept_student_ddah(ddah, offer, signature, date)
    if offer[:ddah_status] == "Pending"
      offer.update_attributes!(ddah_status: "Accepted")
      ddah.update_attributes!(student_signature: signature, student_sign_date: date)
      render status: 200, json: {message: "You have accepted this DDAH.", status: offer[:ddah_status]}
    else
      render status: 404, json: {message: "Error: You cannot accept an unsent DDAH.", status: offer[:ddah_status]}
    end
  end

  def ddah_params
    params.permit(:optional, :scaling_learning)
  end

  def get_all_ddahs(ddahs)
    ddahs.map do |ddah|
      ddah.format
    end
  end

  def get_all_ddah_for_utorid(utorid)
    ddahs = []
    Ddah.all.each do |ddah|
      offer = Offer.find(ddah[:offer_id])
      position = Position.find(offer[:position_id])
      position.instructors.each do |instructor|
        if instructor[:utorid] == utorid
          ddahs.push(ddah)
        end
      end
    end
    return ddahs
  end

  def check_ddah_status(ddahs, status)
    invalid = []
    ddahs.each do |ddah_id|
      ddah = Ddah.find(ddah_id)
      offer = Offer.find(ddah[:offer_id])
      if !(status.include? offer[:ddah_status])
        invalid.push(ddah[:id])
      end
    end
    if invalid.length > 0
      render status: 404, json: {invalid_offers: invalid}
    end
  end

  def clear_ddah(ddah)
    ddah.update_attributes!(
      optional: nil,
      instructor_id: nil,
      tutorial_category: nil,
      department: nil,
      scaling_learning: nil,
    )
    ddah.allocations.each do |allocation|
      ddah.allocation_ids = ddah.allocation_ids - [allocation[:id]]
      allocation.destroy!
    end
    ddah.training_ids = []
    ddah.category_ids = []
  end

  def copy_allocations(model, allocations, remove_attr, add_attr)
    allocations.each do |val|
      val = val.json.except(:id, remove_attr)
      val[add_attr] = model[:id]
      allocation = Allocation.create!(val)
      model.allocations.push(allocation)
    end
  end

  def template_match_offer(template_id, offer)
    position_id = offer[:position_id]
    template = Template.find(template_id)
    return position_id == template[:position_id]
  end

end
