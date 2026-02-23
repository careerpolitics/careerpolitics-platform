require "rails_helper"

RSpec.describe JobPost, type: :model do
  describe "post_type validation" do
    it "allows dynamically defined post types" do
      job_post = build(:job_post, post_type: "result")

      expect(job_post).to be_valid
    end

    it "rejects post types with spaces" do
      job_post = build(:job_post, post_type: "new update")

      expect(job_post).not_to be_valid
      expect(job_post.errors[:post_type]).to be_present
    end
  end
end
