require "rails_helper"

RSpec.describe PushNotifications::CleanupWorker, type: :worker do
  describe "#perform" do
    let(:redis) { instance_double(Redis) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
    end

    it "expires delivered notification hashes with no TTL" do
      allow(redis).to receive(:scan).and_return(["1", ["rpush:notifications:1"]], ["0", []])
      allow(redis).to receive(:ttl).with("rpush:notifications:1").and_return(-1)
      allow(redis).to receive(:type).with("rpush:notifications:1").and_return("hash")
      allow(redis).to receive(:hget).with("rpush:notifications:1", "delivered").and_return("1")
      allow(redis).to receive(:expire)

      described_class.new.perform

      expect(redis).to have_received(:expire).with("rpush:notifications:1", 8.hours.to_i)
    end

    it "does not expire keys that are not delivered hashes with missing TTL" do
      allow(redis).to receive(:scan).and_return(["1", ["rpush:notifications:1"]], ["0", []])
      allow(redis).to receive(:ttl).with("rpush:notifications:1").and_return(20)
      allow(redis).to receive(:type).with("rpush:notifications:1").and_return("string")
      allow(redis).to receive(:hget).with("rpush:notifications:1", "delivered").and_return(nil)
      allow(redis).to receive(:expire)

      described_class.new.perform

      expect(redis).not_to have_received(:expire)
    end
  end
end
