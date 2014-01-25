class CreateStations < ActiveRecord::Migration
  def change
    create_table :stations do |t|
      t.string :name
      t.string :longname
      t.string :state
      t.float :lat
      t.float :lon

      t.timestamps
    end
  end
end
