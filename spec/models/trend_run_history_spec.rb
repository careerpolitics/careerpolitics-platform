require "rails_helper"

RSpec.describe TrendRunHistory do
  describe ".slugify" do
    it "returns a deterministic fallback slug for non-latin trends" do
      slug = described_class.slugify("शिखा वर्मा")

      expect(slug).to start_with("trend-")
      expect(slug.length).to eq(18)
    end
  end
end
