class CreateTrendRunHistories < ActiveRecord::Migration[7.0]
  def change
    create_table :trend_run_histories do |t|
      t.string :trend, null: false
      t.string :trend_slug, null: false
      t.boolean :published, default: false, null: false
      t.timestamps
    end

    add_index :trend_run_histories, :trend_slug
    add_index :trend_run_histories, :created_at
  end
end
