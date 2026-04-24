require "rails_helper"

RSpec.describe PushNotifications::DeliverWorker, type: :worker do
  describe "#perform" do
    it "triggers rpush delivery" do
      allow(Rpush).to receive(:push)

      described_class.new.perform

      expect(Rpush).to have_received(:push)
    end
  end
end
