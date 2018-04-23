class CreateStores < ActiveRecord::Migration[5.2]
  def change
    create_table :stores do |t|
      t.text :area, null: false
      t.text :name, null: false
      t.text :url, null: false
      t.text :coordinates, null: false
      t.decimal :latitude,  precision: 11, scale: 8, null: false
      t.decimal :longitude, precision: 11, scale: 8, null: false
      t.datetime :registered_at, null: false

      t.timestamps null: false
    end
    add_index :stores, [:url], unique: true
  end
end
