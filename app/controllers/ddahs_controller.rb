class DdahsController < ApplicationController
  protect_from_forgery with: :null_session
  include DdahUpdater
  include Authorizer
  include Model
  before_action :cp_access

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
        Ddah.create!(
          offer_id: offer[:id],
          template_id: params[:template_id],
        )
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
    update_form(ddah, param)
  end

  '''
    Template DDAH
  '''
  def apply_template
    # TO-DO
  end

  def new_template
    # TO-DO
  end

  '''
    Send Mails
  '''
  def can_send_ddahs
    # TO-DO
  end

  def send_ddahs
    # TO-DO
  end

  '''
    Nag Mails
  '''
  def can_nag_instructor
    # TO-DO
  end

  def send_nag_instructor
    # TO-DO
  end

  def can_nag_student
    # TO-DO
  end

  def send_nag_student
    # TO-DO
  end


  '''
    Student-Facing
  '''
  def get_ddah_pdf
    # TO-DO
    puts "hello"
  end

  def accept_ddah
    # TO-DO
  end

  private
  def ddah_params
    params.permit(:optional)
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

end