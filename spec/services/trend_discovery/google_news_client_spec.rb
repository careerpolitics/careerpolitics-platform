require "rails_helper"

RSpec.describe TrendDiscovery::GoogleNewsClient do
  describe "#discover" do
    let(:browser_client) { instance_double(TrendDiscovery::SeleniumBrowserClient) }
    let(:client) { described_class.new(browser_client: browser_client) }

    it "parses headlines and resolves google redirect links" do
      html = <<~HTML
        <div class="SoaBEf">
          <a href="/url?q=https://example.com/news-story&sa=U">
            <h3>Recruitment update 2026 announced</h3>
          </a>
          <div class="CEMjEf"><span>Example Times</span></div>
          <div class="GI74Re">Application dates released.</div>
        </div>
      HTML
      allow(browser_client).to receive(:fetch_page).and_return(html)

      result = client.discover(trend: "recruitment update", geo: "IN", language: "en-IN", max_news: 3)

      expect(result.length).to eq(1)
      expect(result.first[:title]).to eq("Recruitment update 2026 announced")
      expect(result.first[:link]).to eq("https://example.com/news-story")
      expect(result.first[:source]).to eq("Example Times")
      expect(result.first[:summary]).to eq("Application dates released.")
    end

    it "returns empty array when fetched html is blank" do
      allow(browser_client).to receive(:fetch_page).and_return(nil)

      expect(client.discover(trend: "recruitment update", geo: "IN", language: "en-IN", max_news: 3)).to eq([])
    end
  end
end
