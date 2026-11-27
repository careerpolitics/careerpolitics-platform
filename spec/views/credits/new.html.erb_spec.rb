require "rails_helper"

# The upstream examples asserted on Stripe Elements JavaScript, which CareerPolitics removed.
RSpec.describe "credits/new" do
  let(:purchaser) { create(:user) }
  let(:credit) { build(:credit) }

  before do
    assign(:purchaser, purchaser)
    assign(:credit, credit)

    sign_in purchaser
  end

  it "renders the purchase page for the purchaser" do
    render

    expect(rendered).to have_content("Purchase credits for @#{purchaser.username}")
  end
end
