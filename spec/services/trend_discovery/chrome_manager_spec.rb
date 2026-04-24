require "rails_helper"

RSpec.describe TrendDiscovery::ChromeManager do
  describe "#resolve_remote_url" do
    it "builds localhost webdriver url from container port binding" do
      manager = described_class.new
      container = instance_double(
        "Docker::Container",
        json: { "NetworkSettings" => { "Ports" => { "4444/tcp" => [{ "HostPort" => "32768" }] } } },
      )
      manager.instance_variable_set(:@container, container)

      remote_url = manager.send(:resolve_remote_url)

      expect(remote_url).to eq("http://localhost:32768/wd/hub")
    end

    it "raises when host port cannot be determined" do
      manager = described_class.new
      container = instance_double(
        "Docker::Container",
        json: { "NetworkSettings" => { "Ports" => { "4444/tcp" => [] } } },
      )
      manager.instance_variable_set(:@container, container)

      expect { manager.send(:resolve_remote_url) }.to raise_error("Cannot determine host port for Chrome container")
    end
  end

  describe "#wait_until_ready!" do
    it "returns true when selenium reports ready" do
      manager = described_class.new
      manager.instance_variable_set(:@remote_url, "http://localhost:32768/wd/hub")
      response = double("response", success?: true, parsed_response: { "value" => { "ready" => true } })
      allow(HTTParty).to receive(:get).and_return(response)

      expect(manager.send(:wait_until_ready!)).to be(true)
    end
  end
end
