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
            <div class="innner-page-main-about-us-content-right-part">
              <div id="MinistryName">Prime Minister's Office</div>
              <h2 id="Titleh2">Airport Inauguration</h2>
              <h3 id="Subtitleh3">New connectivity milestone</h3>
              <div id="PrDateTime">Posted On: 28 MAR 2026 2:23PM by PIB Delhi</div>
              <div id="lg_g">
                <img src="https://static.pib.gov.in/photo.png" alt="event image">
              </div>
              <p>The Ministry announced major infrastructure steps with implementation details and timeline updates for the public.</p>
              <p>The release includes policy objectives, execution details, and expected impact across regions.</p>
              <p>Additional official clarifications were included for citizens and state agencies.</p>
              <iframe src="https://platform.twitter.com/embed/Tweet.html?id=2037787855079305454"></iframe>
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
      expect(result.body).to include("{% card %}")
      expect(result.body).to include("### PIB Announcement Highlights")
      expect(result.body).to include("- Key infrastructure update")
      expect(result.body).to include("![Airport Inauguration](https://static.pib.gov.in/photo.png)")
      expect(result.body).to include("- X/Twitter: https://x.com/i/web/status/2037787855079305454")
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
      allow(ai_client).to receive(:call).with(
        include(
          "[1] Airport Inauguration",
          "URL: https://pib.gov.in/PressReleaseIframePage.aspx?PRID=2",
          "IMAGE_URLS: https://static.pib.gov.in/photo.png",
          "SOCIAL_LINKS: https://x.com/i/web/status/2037787855079305454",
          "Format each topic in a card block",
          "If IMAGE_URLS are available, include markdown images"
        ),
      )
        .and_return("TITLE: T\nTAGS: t\nBODY: B")

      described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate
    end


    it "preserves AI card body and appends media cards when media is missing in AI output" do
      allow(feed_fetcher).to receive(:get).with(described_class::FEED_URL, timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: rss_xml))
      allow(feed_fetcher).to receive(:get).with("https://pib.gov.in/PressReleaseIframePage.aspx?PRID=1", timeout: 10)
        .and_return(instance_double(HTTParty::Response, body: article_html))
      allow(ai_client).to receive(:call).and_return(
        "INCLUDE: 1",
        "TITLE: PIB Card\nTAGS: pib\nBODY: {% card %}\n### Topic\nSummary\n{% endcard %}"
      )

      result = described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate

      expect(result.body.scan("{% card %}").size).to eq(2)
      expect(result.body).to include("### Topic")
      expect(result.body).to include("### Media: Airport Inauguration")
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
