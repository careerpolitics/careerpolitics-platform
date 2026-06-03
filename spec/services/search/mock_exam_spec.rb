require "rails_helper"

RSpec.describe Search::MockExam, type: :service do
  describe "::search_documents" do
    context "when filtering mock exams" do
      it "only returns active and published templates", :aggregate_failures do
        active = create(:mock_exam_template, title: "UPSC Mock Active", active: true, published: true)
        create(:mock_exam_template, title: "UPSC Mock Inactive", active: false, published: true)
        create(:mock_exam_template, :unpublished, title: "UPSC Mock Draft")

        result = described_class.search_documents(term: "UPSC")
        ids = result.map { |r| r[:id] }

        expect(ids).to include(active.id)
        expect(ids.length).to eq(1)
      end

      it "returns all active published templates when no term is given" do
        create_list(:mock_exam_template, 3, active: true, published: true)
        create(:mock_exam_template, :unpublished)

        result = described_class.search_documents
        expect(result.length).to eq(3)
      end
    end

    context "when describing the result format" do
      let!(:tag) { create(:tag, name: "government_exams") }
      let!(:template) do
        create(:mock_exam_template,
               title: "SSC CGL Mock",
               active: true,
               published: true,
               tag: tag)
      end

      it "returns the correct keys" do
        result = described_class.search_documents(term: "SSC")
        expected_keys = %i[
          class_name id title path description total_questions duration_minutes
          difficulty_level exam_category tag_name published_at
          readable_publish_date published_timestamp
        ]
        expect(result.first.keys).to match_array(expected_keys)
      end

      it "returns class_name as MockExamTemplate" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:class_name]).to eq("MockExamTemplate")
      end

      it "returns the correct path" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:path]).to eq("/mock_exams/#{template.slug}")
      end

      it "returns the associated tag name" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:tag_name]).to eq("government_exams")
      end
    end

    context "when searching by term" do
      it "matches against title", :aggregate_failures do
        create(:mock_exam_template, title: "UPSC Prelims Practice", active: true, published: true)

        expect(described_class.search_documents(term: "UPSC")).to be_present
        expect(described_class.search_documents(term: "javascript")).to be_empty
      end

      it "matches against description", :aggregate_failures do
        create(:mock_exam_template,
               title: "General Test",
               description: "Practice for civil services examination",
               active: true,
               published: true)

        expect(described_class.search_documents(term: "civil")).to be_present
        expect(described_class.search_documents(term: "cryptocurrency")).to be_empty
      end

      it "supports prefix matching" do
        create(:mock_exam_template, title: "Railway Recruitment", active: true, published: true)

        expect(described_class.search_documents(term: "Rail")).to be_present
      end
    end

    context "when sorting" do
      it "sorts by created_at descending by default" do
        older = create(:mock_exam_template, title: "Mock Alpha", active: true, published: true,
                       created_at: 2.days.ago)
        newer = create(:mock_exam_template, title: "Mock Beta", active: true, published: true,
                       created_at: 1.hour.ago)

        result = described_class.search_documents(term: "Mock")
        ids = result.map { |r| r[:id] }

        expect(ids).to eq([newer.id, older.id])
      end

      it "respects sort_by and sort_direction params" do
        older = create(:mock_exam_template, title: "Mock Alpha", active: true, published: true,
                       created_at: 2.days.ago)
        newer = create(:mock_exam_template, title: "Mock Beta", active: true, published: true,
                       created_at: 1.hour.ago)

        result = described_class.search_documents(term: "Mock", sort_by: "created_at", sort_direction: "asc")
        ids = result.map { |r| r[:id] }

        expect(ids).to eq([older.id, newer.id])
      end
    end

    context "when paginating" do
      before do
        create_list(:mock_exam_template, 3, active: true, published: true)
      end

      it "returns no results when out of pagination bounds" do
        result = described_class.search_documents(page: 99)
        expect(result).to be_empty
      end

      it "returns paginated results", :aggregate_failures do
        result = described_class.search_documents(page: 0, per_page: 2)
        expect(result.length).to eq(2)

        result = described_class.search_documents(page: 1, per_page: 2)
        expect(result.length).to eq(1)
      end

      it "caps per_page at MAX_PER_PAGE" do
        result = described_class.search_documents(per_page: 9999)
        expect(result.length).to eq(3)
      end
    end
  end
end
