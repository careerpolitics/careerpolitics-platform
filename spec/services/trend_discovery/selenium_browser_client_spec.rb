require "rails_helper"

RSpec.describe TrendDiscovery::SeleniumBrowserClient do
  describe "#create_driver" do
    let(:remote_url) { "http://selenium.example:4444/wd/hub" }
    let(:client) { described_class.new(remote_url: remote_url) }
    let(:options) { instance_double(Selenium::WebDriver::Chrome::Options) }
    let(:driver) { instance_double(Selenium::WebDriver::Driver) }
    let(:exclude_switches) { [] }

    before do
      allow(Selenium::WebDriver::Chrome::Options).to receive(:new).and_return(options)
      allow(options).to receive(:add_option)
      allow(options).to receive(:add_argument)
      allow(options).to receive(:add_preference)
      allow(options).to receive(:exclude_switches).and_return(exclude_switches)

      allow(Selenium::WebDriver).to receive(:for).and_return(driver)
      allow(client).to receive(:apply_stealth)
      allow(client).to receive(:random_browser_profile).and_return(
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ExampleBrowser/1.0",
        platform: "Win32",
        languages: ["en-US", "en"],
      )
    end

    it "does not set non-w3c chrome options for selenium remote" do
      client.send(:create_driver)

      expect(options).to have_received(:add_argument).with("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) ExampleBrowser/1.0")
      expect(options).to have_received(:add_preference).with("intl.accept_languages", "en-US,en")
      expect(Selenium::WebDriver).to have_received(:for).with(
        :remote,
        url: remote_url,
        options: options,
      )
      expect(client).to have_received(:apply_stealth).with(driver, profile: hash_including(platform: "Win32"))
    end
  end

  describe "#build_stealth_script" do
    let(:client) { described_class.new(remote_url: "http://selenium.example:4444/wd/hub") }

    it "renders platform and language values from the selected profile" do
      script = client.send(:build_stealth_script, platform: "MacIntel", languages: ["en-US", "en"])

      expect(script).to include("Object.defineProperty(navigator, 'platform', {get: () => 'MacIntel'});")
      expect(script).to include("Object.defineProperty(navigator, 'languages', {get: () => [\"en-US\",\"en\"]});")
    end
  end
end
