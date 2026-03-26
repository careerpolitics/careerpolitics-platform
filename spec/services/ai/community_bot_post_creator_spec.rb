require "rails_helper"

RSpec.describe Ai::CommunityBotPostCreator, type: :service do
  let(:ai_client) { instance_double(Ai::Base) }
  let(:ai_context) { "Create a weekly update for the Ruby on Rails community" }

  describe "#generate" do
    it "returns parsed title, body, and tags" do
      response = "TITLE: Rails Weekly\nTAGS: rails, ruby, testing\nBODY: # This Week in Rails\nGreat updates!"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: ai_context, ai_client: ai_client).generate

      expect(result.title).to eq("Rails Weekly")
      expect(result.body).to eq("# This Week in Rails\nGreat updates!")
      expect(result.tags).to eq(%w[rails ruby testing])
    end

    it "falls back to provided tags when response tags are missing" do
      response = "TITLE: Rails Weekly\nBODY: # This Week in Rails"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: ai_context, tags: "rails, ruby", ai_client: ai_client).generate

      expect(result.tags).to eq(%w[rails ruby])
    end

    it "returns nil when context is blank" do
      result = described_class.new(ai_context: "", ai_client: ai_client).generate
      expect(result).to be_nil
    end

    it "adds additional instructions to the prompt" do
      service = described_class.new(
        ai_context: ai_context,
        additional_instructions: "Target beginner developers",
        ai_client: ai_client,
      )

      allow(ai_client).to receive(:call).with(include("Target beginner developers")).and_return("TITLE: T\nTAGS: t\nBODY: B")

      service.generate
    end

    it "requests generated tags when tags are not provided" do
      service = described_class.new(ai_context: ai_context, ai_client: ai_client)

      allow(ai_client).to receive(:call).with(include("Generate 1-4 relevant tags")).and_return("TITLE: T\nTAGS: t\nBODY: B")

      service.generate
    end

    it "uses fixed tags from input when provided" do
      service = described_class.new(ai_context: ai_context, tags: "daily-quiz, current-affairs", ai_client: ai_client)

      allow(ai_client).to receive(:call).with(include("Use these tags exactly")).and_return("TITLE: T\nTAGS: t\nBODY: B")

      service.generate
    end

    it "limits tags to 4 and normalizes formatting" do
      response = "TITLE: T
TAGS: #News, WORLD, analysis, policy, extra
BODY: B"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: ai_context, ai_client: ai_client).generate

      expect(result.tags).to eq(%w[news world analysis policy])
    end

    it "uses context-derived fallback tags when no tags are present" do
      response = "TITLE: T
BODY: B"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: "Global economy update for developers", ai_client: ai_client).generate

      expect(result.tags).to be_present
    end

  end
end
