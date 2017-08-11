class CreateOffers < ActiveRecord::Migration[5.1]
  def change
    create_table :offers do |t|
      t.references :position, index: true
      t.references :applicant, index: true
      t.boolean :objection, default: false
      t.integer :hours, null: false
      t.integer :year
      t.string :session
      t.string :status, default: "Unsent"

      t.timestamps
    end
  end
end
