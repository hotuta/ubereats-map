class AddReviewsToStores < ActiveRecord::Migration[5.2]
  def change
    add_column :stores, :review, :integer
    add_column :stores, :star, :float
  end
end
