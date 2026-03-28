require "rails_helper"

RSpec.describe Ai::CommunityBotPibAnnouncementPostCreator, type: :service do
  let(:ai_client) { instance_double(Ai::Base) }
  let(:feed_fetcher) { class_double(HTTParty) }
  let(:ai_context) { "Summarize the most important PIB announcements for UPSC aspirants" }
  let(:feed_response) { instance_double(HTTParty::Response, body: "<xml></xml>") }

  describe "#generate" do
    it "fetches feed items and returns parsed title, body, and tags" do
      item_one = instance_double(Feedjira::Parser::RSSEntry, title: "Cabinet approves policy", url: "https://www.pib.gov.in/1")
      item_two = instance_double(Feedjira::Parser::RSSEntry, title: "Ministry launches portal", url: "https://www.pib.gov.in/2")
      parsed_feed = instance_double(Feedjira::Parser::RSS, entries: [item_one, item_two])

      allow(feed_fetcher).to receive(:get).and_return(feed_response)
      allow(Feedjira).to receive(:parse).and_return(parsed_feed)
      allow(ai_client).to receive(:call).and_return("TITLE: PIB Daily Brief\nTAGS: pib, government\nBODY: - Key updates")

      result = described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate

      expect(result.title).to eq("PIB Daily Brief")
      expect(result.body).to eq("- Key updates")
      expect(result.tags).to eq(%w[pib government])
    end

    it "includes feed titles and URLs in the AI prompt" do
      item = instance_double(Feedjira::Parser::RSSEntry, title: "Health mission update", url: "https://www.pib.gov.in/health")
      parsed_feed = instance_double(Feedjira::Parser::RSS, entries: [item])

      allow(feed_fetcher).to receive(:get).and_return(feed_response)
      allow(Feedjira).to receive(:parse).and_return(parsed_feed)
      allow(ai_client).to receive(:call).with(include("Health mission update", "https://www.pib.gov.in/health")).and_return("TITLE: T\nTAGS: t\nBODY: B")

      described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate
    end

    it "returns nil when the feed has no entries" do
      parsed_feed = instance_double(Feedjira::Parser::RSS, entries: [])

      allow(feed_fetcher).to receive(:get).and_return(feed_response)
      allow(Feedjira).to receive(:parse).and_return(parsed_feed)

      result = described_class.new(ai_context: ai_context, ai_client: ai_client, feed_fetcher: feed_fetcher).generate

      expect(result).to be_nil
      expect(ai_client).not_to have_received(:call)
    end
  end
end
