require "rails_helper"

RSpec.describe TrendDiscovery::GoogleTrendsClient do
  describe "#discover" do
    let(:browser_client) { instance_double(TrendDiscovery::SeleniumBrowserClient) }

    it "returns cleaned trend hashes from html data-term nodes" do
      html = <<~HTML
        <div data-term="  UP Board Result 2026  "></div>
        <div data-term="SSC CGL"></div>
      HTML
      allow(browser_client).to receive(:fetch_page).and_return(html)

      result = described_class.new(browser_client: browser_client).discover(geo: "IN", language: "en-IN", max_trends: 2)

      expect(result).to eq([
        { name: "UP Board Result 2026", slug: "up-board-result-2026", keywords: ["UP Board Result 2026"] },
        { name: "SSC CGL", slug: "ssc-cgl", keywords: ["SSC CGL"] },
      ])
    end

    it "falls back to ai extraction and parses fenced json response" do
      html = <<~HTML
        <table>
          <tbody>
            <tr><td>searches</td><td>UP Board</td></tr>
          </tbody>
        </table>
      HTML
      ai_client = instance_double(Ai::Base)
      allow(browser_client).to receive(:fetch_page).and_return(html)
      allow(ai_client).to receive(:call).and_return(<<~JSON)
        ```json
        {"topics":[{"name":"UP Board Result","keywords":["UP result","UP board"]}]}
        ```
      JSON

      result = described_class.new(browser_client: browser_client, ai_client: ai_client)
        .discover(geo: "IN", language: "en-IN", max_trends: 3)

      expect(result).to eq([
        { name: "UP Board Result", slug: "up-board-result", keywords: ["UP Board Result", "UP result", "UP board"] },
      ])
    end
  end
end
