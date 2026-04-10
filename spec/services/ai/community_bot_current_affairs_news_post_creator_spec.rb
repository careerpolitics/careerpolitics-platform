require "rails_helper"

RSpec.describe Ai::CommunityBotCurrentAffairsNewsPostCreator, type: :service do
  let(:ai_client) { instance_double(Ai::Base) }
  let(:ai_context) { "Summarize important Indian current affairs from yesterday for government exam aspirants" }

  describe "#generate" do
    it "returns parsed title, body, and tags" do
      response = "TITLE: Current Affairs Digest\nTAGS: current-affairs, india\nBODY: - Key update"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: ai_context, ai_client: ai_client).generate

      expect(result.title).to eq("Current Affairs Digest")
      expect(result.body).to eq("- Key update")
      expect(result.tags).to eq(%w[current-affairs india])
    end

    it "injects current date context into the prompt" do
      service = described_class.new(ai_context: ai_context, ai_client: ai_client)

      allow(ai_client).to receive(:call).with(include("Today's date (UTC):")).and_return("TITLE: T\nTAGS: t\nBODY: B")

      service.generate
    end
  end
end
