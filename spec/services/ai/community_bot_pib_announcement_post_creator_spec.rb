require "rails_helper"

RSpec.describe Ai::CommunityBotPibAnnouncementPostCreator, type: :service do
  let(:ai_client) { instance_double(Ai::Base) }
  let(:feed_fetcher) { class_double(HTTParty) }
  let(:ai_context) { "Summarize PIB announcements relevant for civil services aspirants" }

  describe "#generate" do
    let(:rss_xml) do
      <<~XML
        <rss version="2.0">
          <channel>
            <item>
              <title>NHAI Awards Contract</title>
              <link>https://pib.gov.in/PressReleaseIframePage.aspx?PRID=1</link>
            </item>
            <item>
              <title>Airport Inauguration Update</title>
              <link>https://pib.gov.in/PressReleaseIframePage.aspx?PRID=2</link>
            </item>
          </channel>
        </rss>
      XML
    end

    let(:article_html) do
      <<~HTML
        <html>
          <body>
            <div id="printPreview">
              The Ministry announced major infrastructure steps with implementation details and timeline updates for the public.
              The release includes policy objectives, execution details, and expected impact across regions.
              Additional official clarifications were included for citizens and state agencies.
            </div>
          </body>
        </html>
      HTML
    end

    it "parses RSS, filters with AI, fetches selected article pages, and returns a generated post" do
      allow(feed_fetcher).to receive(:get).with(described_class::FEED_URL, timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: rss_xml))
      allow(feed_fetcher).to receive(:get).with("https://pib.gov.in/PressReleaseIframePage.aspx?PRID=1", timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: article_html))
      allow(ai_client).to receive(:call).and_return(
        "INCLUDE: 1",
        "TITLE: PIB Daily Brief\nTAGS: pib, announcements\nBODY: - Key infrastructure update"
      )

      result = described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate

      expect(result.title).to eq("PIB Daily Brief")
      expect(result.body).to eq("- Key infrastructure update")
      expect(result.tags).to eq(%w[pib announcements])
      expect(feed_fetcher).to have_received(:get).with("https://pib.gov.in/PressReleaseIframePage.aspx?PRID=1", timeout: 10)
    end

    it "includes RSS item numbering in the filter prompt" do
      allow(feed_fetcher).to receive(:get).with(described_class::FEED_URL, timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: rss_xml))
      allow(feed_fetcher).to receive(:get).with("https://pib.gov.in/PressReleaseIframePage.aspx?PRID=2", timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: article_html))
      allow(ai_client).to receive(:call).with(include("1. NHAI Awards Contract", "2. Airport Inauguration Update"))
        .and_return("INCLUDE: 2")
      allow(ai_client).to receive(:call).with(include("[1] Airport Inauguration Update", "URL: https://pib.gov.in/PressReleaseIframePage.aspx?PRID=2"))
        .and_return("TITLE: T\nTAGS: t\nBODY: B")

      described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate
    end

    it "returns nil when AI excludes all feed items" do
      allow(feed_fetcher).to receive(:get).with(described_class::FEED_URL, timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: rss_xml))
      allow(ai_client).to receive(:call).and_return("INCLUDE: NONE")

      result = described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate

      expect(result).to be_nil
    end
  end
end
