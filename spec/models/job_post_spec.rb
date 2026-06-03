require "rails_helper"

RSpec.describe JobPost, type: :model do
  subject { build(:job_post) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_uniqueness_of(:slug) }

    it "is invalid without a slug on an existing record" do
      job = create(:job_post)
      job.slug = nil
      expect(job).not_to be_valid
      expect(job.errors[:slug]).to be_present
    end

    it "validates link presence when published" do
      job = build(:job_post, published: true, link: nil)
      expect(job).not_to be_valid
      expect(job.errors[:link]).to be_present
    end

    it "allows nil link when unpublished" do
      job = build(:job_post, published: false, link: nil)
      job.valid?
      expect(job.errors[:link]).to be_empty
    end

    it "accepts relative URL links" do
      job = build(:job_post, link: "/jobs/test")
      expect(job).to be_valid
    end

    it "accepts absolute URL links" do
      job = build(:job_post, link: "https://example.com/apply")
      expect(job).to be_valid
    end

    it "rejects invalid link format" do
      job = build(:job_post, link: "ftp://invalid.com")
      expect(job).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "scopes" do
    it ".published returns only published posts" do
      create(:job_post, published: true, approved: true)
      create(:job_post, published: false, approved: true)

      expect(described_class.published.count).to eq(1)
    end

    it ".approved returns only approved posts" do
      create(:job_post, published: true, approved: true)
      create(:job_post, published: true, approved: false)

      expect(described_class.approved.count).to eq(1)
    end

    it ".available returns only published and approved posts" do
      create(:job_post, published: true, approved: true)
      create(:job_post, published: true, approved: false)
      create(:job_post, published: false, approved: true)

      expect(described_class.available.count).to eq(1)
    end

    it ".by_post_type filters by post_type" do
      create(:job_post, post_type: "admit_card")
      create(:job_post, post_type: "new_update")

      expect(described_class.by_post_type("admit_card").count).to eq(1)
    end
  end

  describe "#path" do
    it "returns /jobs/:slug" do
      job = create(:job_post, slug: "ssc-cgl-2025")
      expect(job.path).to eq("/jobs/ssc-cgl-2025")
    end
  end

  describe "#badge_type" do
    it "returns 'new' when published within last 3 days" do
      job = create(:job_post, published_at: 1.day.ago)
      expect(job.badge_type).to eq("new")
    end

    it "returns nil for older posts" do
      job = create(:job_post, published_at: 5.days.ago)
      expect(job.badge_type).to be_nil
    end
  end

  describe "#available?" do
    it "returns true when published and approved" do
      job = create(:job_post, published: true, approved: true)
      expect(job.available?).to be true
    end

    it "returns false when not published" do
      job = create(:job_post, published: false, approved: true)
      expect(job.available?).to be false
    end

    it "returns false when not approved" do
      job = create(:job_post, published: true, approved: false)
      expect(job.available?).to be false
    end
  end

  describe "#slug auto-generation" do
    it "generates slug from title when not provided" do
      job = create(:job_post, title: "UPSC Notification 2025", slug: nil)
      expect(job.slug).to start_with("upsc-notification-2025")
    end

    it "does not overwrite existing slug" do
      job = create(:job_post, slug: "custom-slug-123")
      expect(job.slug).to eq("custom-slug-123")
    end

    it "appends counter for duplicate slugs" do
      create(:job_post, slug: "duplicate-slug")
      job2 = create(:job_post, title: "Duplicate Slug", slug: nil)
      expect(job2.slug).to eq("duplicate-slug-1")
    end
  end

  describe ".search_job_posts" do
    it "finds posts by title" do
      job = create(:job_post, title: "Railway Board Vacancy")
      results = described_class.search_job_posts("Railway")
      expect(results).to include(job)
    end

    it "finds posts by description" do
      job = create(:job_post, description: "Apply online for clerk posts")
      results = described_class.search_job_posts("clerk")
      expect(results).to include(job)
    end

    it "finds posts by organization_name" do
      job = create(:job_post, organization_name: "Reserve Bank of India")
      results = described_class.search_job_posts("Reserve")
      expect(results).to include(job)
    end

    it "finds posts by category" do
      job = create(:job_post, category: "Banking")
      results = described_class.search_job_posts("Banking")
      expect(results).to include(job)
    end

    it "supports prefix matching" do
      job = create(:job_post, title: "Defence Ministry")
      results = described_class.search_job_posts("Defen")
      expect(results).to include(job)
    end

    it "does not return non-matching posts" do
      create(:job_post, title: "Banking Exam", description: "Finance")
      results = described_class.search_job_posts("cryptocurrency")
      expect(results).to be_empty
    end
  end

  describe "#employment_type_schema_value" do
    it "maps full_time to FULL_TIME" do
      job = build(:job_post, employment_type: "full_time")
      expect(job.employment_type_schema_value).to eq("FULL_TIME")
    end

    it "returns nil when employment_type is blank" do
      job = build(:job_post, employment_type: nil)
      expect(job.employment_type_schema_value).to be_nil
    end
  end

  describe "#related_jobs" do
    it "returns available jobs with the same post_type excluding self" do
      job1 = create(:job_post, post_type: "new_update", published: true, approved: true)
      job2 = create(:job_post, post_type: "new_update", published: true, approved: true)
      create(:job_post, post_type: "admit_card", published: true, approved: true)

      expect(job1.related_jobs).to include(job2)
      expect(job1.related_jobs).not_to include(job1)
    end
  end
end
