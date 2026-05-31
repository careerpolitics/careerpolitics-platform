class AddPoolSetToMockExamAttempts < ActiveRecord::Migration[7.0]
  def change
    add_column :mock_exam_attempts, :pool_set, :integer
  end
end
