class CreateObservations < ActiveRecord::Migration
  def change
    create_table :observations do |t|
      t.belongs_to :station
      t.timestamp :validtime
      t.float :tmp
      t.float :dwp
      t.float :winddir
      t.float :windspd
      t.float :p_01

      t.timestamps
    end
  end
end
