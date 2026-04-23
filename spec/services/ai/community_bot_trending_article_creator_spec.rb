require "rails_helper"

RSpec.describe Ai::CommunityBotTrendingArticleCreator do
  describe "#sanitize_tags" do
    it "strips disallowed characters so generated tags pass article validations" do
      service = described_class.new(ai_context: "Career platform")

      sanitized_tags = service.send(:sanitize_tags, ["up-board-result", "career-guidance", "government-jobs", "result"])

      expect(sanitized_tags).to eq(%w[upboardresult careerguidance governmentjobs result])
      expect(Article.new(tag_list: sanitized_tags)).to be_valid
    end
  end

  describe "#generate" do
    let(:ai_client) { instance_double(Ai::Base) }
    let(:chrome_manager) { instance_double(TrendDiscovery::ChromeManager, start!: "http://selenium:4444/wd/hub", stop!: true) }
    let(:browser) { instance_double(TrendDiscovery::SeleniumBrowserClient) }
    let(:news_client) { instance_double(TrendDiscovery::GoogleNewsClient) }
    let(:enricher) { instance_double(TrendDiscovery::HeadlineEnricher) }

    let(:service) do
      described_class.new(
        ai_context: "Career platform",
        ai_client: ai_client,
      )
    end

    it "retries AI generation when JSON parsing fails" do
      trend = { name: "kseab", slug: "kseab" }
      headlines = [{ title: "Headline", source: "Source" }]
      parsed_result = described_class::PostResult.new(title: "Title", body: "Body", tags: "career", cover_image: nil)

      allow(TrendDiscovery::ChromeManager).to receive(:new).and_return(chrome_manager)
      allow(TrendDiscovery::SeleniumBrowserClient).to receive(:new).and_return(browser)
      allow(TrendDiscovery::GoogleNewsClient).to receive(:new).and_return(news_client)
      allow(TrendDiscovery::HeadlineEnricher).to receive(:new).and_return(enricher)

      allow(service).to receive(:discover_trends).and_return([trend])
      allow(service).to receive(:pick_fresh_trends).and_return([trend])
      allow(news_client).to receive(:discover).and_return(headlines)
      allow(enricher).to receive(:enrich).and_return(headlines)
      allow(service).to receive(:fetch_platform_tags).and_return([])
      allow(service).to receive(:build_prompt).and_return("BASE PROMPT")
      allow(service).to receive(:parse_response).and_return(nil, parsed_result)
      allow(TrendRunHistory).to receive(:create!)

      allow(ai_client).to receive(:call).and_return("bad payload", "good payload")

      result = service.generate

      expect(result).to eq([parsed_result])
      expect(ai_client).to have_received(:call).with("BASE PROMPT", response_mime_type: "application/json").once
      expect(ai_client).to have_received(:call).with(include("RETRY INSTRUCTION (CRITICAL):"), response_mime_type: "application/json").once
    end

    it "records a fallback trend_slug when selected trend slug is blank" do
      trend = { name: "शिखा वर्मा", slug: "" }
      parsed_result = described_class::PostResult.new(title: "Title", body: "Body", tags: "career", cover_image: nil)

      allow(TrendDiscovery::ChromeManager).to receive(:new).and_return(chrome_manager)
      allow(TrendDiscovery::SeleniumBrowserClient).to receive(:new).and_return(browser)
      allow(TrendDiscovery::GoogleNewsClient).to receive(:new).and_return(news_client)
      allow(TrendDiscovery::HeadlineEnricher).to receive(:new).and_return(enricher)

      allow(service).to receive(:discover_trends).and_return([trend])
      allow(service).to receive(:pick_fresh_trends).and_return([trend])
      allow(news_client).to receive(:discover).and_return([])
      allow(enricher).to receive(:enrich).and_return([])
      allow(service).to receive(:fetch_platform_tags).and_return([])
      allow(service).to receive(:build_prompt).and_return("BASE PROMPT")
      allow(service).to receive(:parse_response).and_return(parsed_result)
      allow(ai_client).to receive(:call).and_return("good payload")

      allow(TrendRunHistory).to receive(:create!)

      result = service.generate

      expect(TrendRunHistory).to have_received(:create!).with(
        trend: "शिखा वर्मा",
        trend_slug: start_with("trend-"),
        published: true,
      )
      expect(result).to eq([parsed_result])
    end

    it "generates an article result for each fresh trend" do
      trend_one = { name: "trend one", slug: "trend-one" }
      trend_two = { name: "trend two", slug: "trend-two" }
      parsed_result_one = described_class::PostResult.new(title: "Title 1", body: "Body 1", tags: "career", cover_image: nil)
      parsed_result_two = described_class::PostResult.new(title: "Title 2", body: "Body 2", tags: "jobs", cover_image: nil)

      allow(TrendDiscovery::ChromeManager).to receive(:new).and_return(chrome_manager)
      allow(TrendDiscovery::SeleniumBrowserClient).to receive(:new).and_return(browser)
      allow(TrendDiscovery::GoogleNewsClient).to receive(:new).and_return(news_client)
      allow(TrendDiscovery::HeadlineEnricher).to receive(:new).and_return(enricher)

      allow(service).to receive(:discover_trends).and_return([trend_one, trend_two])
      allow(service).to receive(:pick_fresh_trends).and_return([trend_one, trend_two])
      allow(news_client).to receive(:discover).and_return([])
      allow(enricher).to receive(:enrich).and_return([])
      allow(service).to receive(:fetch_platform_tags).and_return([])
      allow(service).to receive(:parse_response).and_return(parsed_result_one, parsed_result_two)
      allow(ai_client).to receive(:call).and_return("payload one", "payload two")
      allow(TrendRunHistory).to receive(:create!)

      result = service.generate

      expect(result).to eq([parsed_result_one, parsed_result_two])
      expect(TrendRunHistory).to have_received(:create!).twice
    end
  end
end
