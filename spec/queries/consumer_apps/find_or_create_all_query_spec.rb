require "rails_helper"

RSpec.describe ConsumerApps::FindOrCreateAllQuery, type: :query do
  let!(:consumer_app) { create(:consumer_app) }

  it "fetches all ConsumerApp including the Forem apps" do
    base_count = ConsumerApp.where.not(app_bundle: ConsumerApp::FOREM_BUNDLE).count
    ConsumerApp.where(app_bundle: ConsumerApp::FOREM_BUNDLE).delete_all

    all_consumer_apps = described_class.call
    result_bundles = all_consumer_apps.map(&:app_bundle).uniq
    result_team_ids = all_consumer_apps.map(&:team_id).uniq

    # Must return all existing non-Forem apps + every ConsumerApp::FOREM_APP_PLATFORMS
    expect(all_consumer_apps.count).to eq(base_count + ConsumerApp::FOREM_APP_PLATFORMS.count)
    # Must include the consumer_app and Forem App bundles
    expect(result_bundles).to include(consumer_app.app_bundle, ConsumerApp::FOREM_BUNDLE)
    # Must include the Forem Team ID
    expect(result_team_ids).to include(ConsumerApp::FOREM_TEAM_ID)
  end
end
