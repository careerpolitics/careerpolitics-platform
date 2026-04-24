require "rails_helper"

RSpec.describe TrendRunHistory do
  describe ".clean" do
    it "normalizes surrounding and repeated whitespace" do
      expect(described_class.clean("  up   board   result  ")).to eq("up board result")
    end
  end

  describe ".slugify" do
    it "creates a normalized slug for latin trends" do
      slug = described_class.slugify("  UP Board Result 2026!  ")

      expect(slug).to eq("up-board-result-2026")
    end

    it "returns a deterministic fallback slug for non-latin trends" do
      slug = described_class.slugify("शिखा वर्मा")

      expect(slug).to start_with("trend-")
      expect(slug.length).to eq(18)
    end
  end

  describe ".fresh?" do
    it "returns false when the slug was used within the cooldown window" do
      described_class.create!(trend: "UP Board", trend_slug: "up-board", published: true)

      expect(described_class.fresh?("up-board", 48)).to be(false)
    end

    it "returns true when the slug has not been used in the cooldown window" do
      expect(described_class.fresh?("brand-new-trend", 48)).to be(true)
    end
  end

  describe ".used_since" do
    it "returns a unique set of trend slugs within the cutoff window" do
      recent = 1.hour.ago
      cutoff = 3.hours.ago

      described_class.create!(trend: "UP Board 1", trend_slug: "up-board", published: true, created_at: recent)
      described_class.create!(trend: "UP Board 2", trend_slug: "up-board", published: true, created_at: recent)
      described_class.create!(trend: "Old Trend", trend_slug: "old-trend", published: true, created_at: 2.days.ago)

      expect(described_class.used_since(cutoff)).to eq(["up-board"].to_set)
    end
  end
end
