require "rails_helper"

RSpec.describe Search::JobPost, type: :service do
  describe "::search_documents" do
    context "when filtering job posts" do
      it "only returns published and approved job posts", :aggregate_failures do
        available = create(:job_post, title: "Ruby Developer", published: true, approved: true)
        create(:job_post, title: "Ruby Intern", published: false, approved: true)
        create(:job_post, title: "Ruby Lead", published: true, approved: false)

        result = described_class.search_documents(term: "Ruby")
        ids = result.map { |r| r[:id] }

        expect(ids).to include(available.id)
        expect(ids.length).to eq(1)
      end

      it "returns all available job posts when no term is given" do
        create_list(:job_post, 3, published: true, approved: true)
        create(:job_post, published: false, approved: true)

        result = described_class.search_documents
        expect(result.length).to eq(3)
      end
    end

    context "when describing the result format" do
      let!(:job) do
        create(:job_post,
               title: "SSC Clerk Recruitment",
               description: "Apply for clerk posts",
               organization_name: "Staff Selection Commission",
               category: "Government",
               post_type: "online_form",
               location: "Delhi",
               salary_range: "25000-35000",
               published: true,
               approved: true)
      end

      it "returns the correct keys" do
        result = described_class.search_documents(term: "SSC")
        expected_keys = %i[
          class_name id title path description organization_name category
          post_type location salary_range published_at
          readable_publish_date published_timestamp
        ]
        expect(result.first.keys).to match_array(expected_keys)
      end

      it "returns class_name as JobPost" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:class_name]).to eq("JobPost")
      end

      it "returns the correct path" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:path]).to eq("/jobs/#{job.slug}")
      end

      it "returns organization_name and category" do
        result = described_class.search_documents(term: "SSC")
        expect(result.first[:organization_name]).to eq("Staff Selection Commission")
        expect(result.first[:category]).to eq("Government")
      end
    end

    context "when searching by term" do
      it "matches against title", :aggregate_failures do
        create(:job_post, title: "Railway Board Recruitment", published: true, approved: true)

        expect(described_class.search_documents(term: "Railway")).to be_present
        expect(described_class.search_documents(term: "cryptocurrency")).to be_empty
      end

      it "matches against description" do
        create(:job_post, title: "Generic Post", description: "Central government vacancy notification",
               published: true, approved: true)

        expect(described_class.search_documents(term: "vacancy")).to be_present
      end

      it "matches against organization_name" do
        create(:job_post, title: "Clerk Post", organization_name: "Reserve Bank of India",
               published: true, approved: true)

        expect(described_class.search_documents(term: "Reserve")).to be_present
      end

      it "matches against category" do
        create(:job_post, title: "Analyst Role", category: "Banking",
               published: true, approved: true)

        expect(described_class.search_documents(term: "Banking")).to be_present
      end

      it "supports prefix matching" do
        create(:job_post, title: "Defence Ministry Recruitment", published: true, approved: true)

        expect(described_class.search_documents(term: "Defen")).to be_present
      end
    end

    context "when sorting" do
      it "uses recent scope by default" do
        older = create(:job_post, title: "Job Alpha", published: true, approved: true,
                       position: 2, published_at: 2.days.ago)
        newer = create(:job_post, title: "Job Beta", published: true, approved: true,
                       position: 1, published_at: 1.hour.ago)

        result = described_class.search_documents(term: "Job")
        ids = result.map { |r| r[:id] }

        expect(ids.first).to eq(newer.id)
      end

      it "respects sort_by published_at with sort_direction" do
        older = create(:job_post, title: "Job Alpha", published: true, approved: true,
                       published_at: 2.days.ago)
        newer = create(:job_post, title: "Job Beta", published: true, approved: true,
                       published_at: 1.hour.ago)

        result = described_class.search_documents(term: "Job", sort_by: "published_at", sort_direction: "asc")
        ids = result.map { |r| r[:id] }

        expect(ids).to eq([older.id, newer.id])
      end
    end

    context "when paginating" do
      before do
        create_list(:job_post, 3, published: true, approved: true)
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
