require "rails_helper"

RSpec.describe MockExamTemplate, type: :model do
  let(:template) { create(:mock_exam_template) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:slug) }

    it "validates uniqueness of slug" do
      create(:mock_exam_template, slug: "duplicate-slug")
      duplicate = build(:mock_exam_template, slug: "duplicate-slug")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include("has already been taken")
    end

    it { is_expected.to validate_presence_of(:total_questions) }
    it { is_expected.to validate_presence_of(:duration_minutes) }
    it { is_expected.to validate_presence_of(:marks_per_correct) }
    it { is_expected.to validate_presence_of(:negative_marks_per_wrong) }
    it { is_expected.to validate_presence_of(:sections_config) }
    it { is_expected.to validate_numericality_of(:total_questions).is_greater_than(0).only_integer }
    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0).only_integer }
  end

  describe "associations" do
    it { is_expected.to have_many(:mock_exam_questions).dependent(:destroy) }
    it { is_expected.to have_many(:mock_exam_attempts).dependent(:destroy) }
    it { is_expected.to have_one(:mock_exam_template_stat).dependent(:destroy) }
    it { is_expected.to belong_to(:subforem).optional }
    it { is_expected.to belong_to(:created_by).optional }
  end

  describe "#slug" do
    it "is auto-generated from title on create" do
      t = create(:mock_exam_template, title: "UPSC Prelims Mock", slug: nil)
      expect(t.slug).to start_with("upsc-prelims-mock-")
    end

    it "is not overwritten if already present" do
      t = create(:mock_exam_template, slug: "custom-slug")
      expect(t.slug).to eq("custom-slug")
    end
  end

  describe "#max_possible_score" do
    it "returns total_questions * marks_per_correct" do
      expect(template.max_possible_score).to eq(template.total_questions * template.marks_per_correct)
    end
  end

  describe "#pool_questions" do
    it "returns only questions with nil attempt_id" do
      create(:mock_exam_question, mock_exam_template: template, mock_exam_attempt: nil)
      attempt = create(:mock_exam_attempt, mock_exam_template: template)
      create(:mock_exam_question, mock_exam_template: template, mock_exam_attempt: attempt)

      expect(template.pool_questions.count).to eq(1)
    end
  end

  describe "#pool_ready?" do
    it "returns true when pool has enough questions" do
      template.total_questions.times do |i|
        create(:mock_exam_question, mock_exam_template: template, position: i + 1,
                                    set_published: true)
      end
      expect(template.pool_ready?).to be(true)
    end

    it "returns false when pool is too small" do
      expect(template.pool_ready?).to be(false)
    end
  end

  describe "scopes" do
    it ".active_published returns only active+published templates" do
      create(:mock_exam_template, active: true, published: true)
      create(:mock_exam_template, :unpublished)
      create(:mock_exam_template, active: false, published: true)

      expect(described_class.active_published.count).to eq(1)
    end
  end
end
