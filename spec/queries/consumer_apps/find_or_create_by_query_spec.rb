require "rails_helper"

RSpec.describe ConsumerApps::FindOrCreateByQuery, type: :query do
  context "when fetching the Forem app" do
    it "recreates the record if it doesn't exist" do
      ConsumerApp.ios.where(app_bundle: ConsumerApp::FOREM_BUNDLE).delete_all

      expect do
        app = described_class.call(
          app_bundle: ConsumerApp::FOREM_BUNDLE,
          platform: :ios,
        )
        expect(app).to be_instance_of(ConsumerApp)
        expect(app.team_id).to eq(ConsumerApp::FOREM_TEAM_ID)
      end.to change { ConsumerApp.ios.where(app_bundle: ConsumerApp::FOREM_BUNDLE).count }.by(1)
    end
  end

  context "when fetching other ConsumerApps" do
    it "returns the requested ConsumerApp" do
      consumer_app = create(:consumer_app)
      expect do
        result = described_class.call(
          app_bundle: consumer_app.app_bundle,
          platform: consumer_app.platform,
        )
        expect(result).to be_instance_of(ConsumerApp)
        expect(result.id).to eq(consumer_app.id)
      end.not_to change(ConsumerApp, :count)
    end
  end
end
