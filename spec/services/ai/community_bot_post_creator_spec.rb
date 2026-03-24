require "rails_helper"

RSpec.describe Ai::CommunityBotPostCreator, type: :service do
  let(:ai_client) { instance_double(Ai::Base) }
  let(:ai_context) { "Create a weekly update for the Ruby on Rails community" }

  describe "#generate" do
    it "returns parsed title and body" do
      response = "TITLE: Rails Weekly\nBODY: # This Week in Rails\nGreat updates!"
      allow(ai_client).to receive(:call).and_return(response)

      result = described_class.new(ai_context: ai_context, ai_client: ai_client).generate

      expect(result.title).to eq("Rails Weekly")
      expect(result.body).to eq("# This Week in Rails\nGreat updates!")
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

      allow(ai_client).to receive(:call).with(include("Target beginner developers")).and_return("TITLE: T\nBODY: B")

      service.generate
    end
  end
end
