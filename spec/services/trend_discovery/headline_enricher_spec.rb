require "rails_helper"

RSpec.describe TrendDiscovery::HeadlineEnricher do
  describe "#enrich" do
    it "returns empty array when headlines are blank" do
      expect(described_class.new.enrich([])).to eq([])
    end

    it "adds extracted article details when fetch succeeds" do
      html = <<~HTML
        <html>
          <head>
            <meta property="og:description" content="Official update summary" />
            <meta property="og:image" content="https://cdn.example.com/news.jpg" />
          </head>
          <body>
            <article>
              <p>This paragraph is deliberately long enough to be captured as article content by the enricher parser logic.</p>
            </article>
          </body>
        </html>
      HTML
      response = double("response", success?: true, body: html)
      allow(HTTParty).to receive(:get).and_return(response)

      headlines = [{ source: "Example", link: "https://example.com/news", summary: "fallback summary" }]
      result = described_class.new.enrich(headlines)

      expect(result.first.dig(:article_details, :description)).to eq("Official update summary")
      expect(result.first.dig(:article_details, :media_urls)).to include("https://cdn.example.com/news.jpg")
      expect(result.first.dig(:article_details, :media_type)).to eq("image")
    end

    it "returns original headline when fetch raises an error" do
      headline = { source: "Example", link: "https://example.com/news" }
      allow(HTTParty).to receive(:get).and_raise(StandardError, "network timeout")

      result = described_class.new.enrich([headline])

      expect(result).to eq([headline])
    end
  end
end
