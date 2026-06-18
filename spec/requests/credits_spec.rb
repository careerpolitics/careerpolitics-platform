require "rails_helper"

RSpec.describe "Credits" do
  describe "GET /credits" do
    let(:user) { create(:user) }
    let(:org_member) { create(:user, :org_member) }
    let(:org_admin) { create(:user, :org_admin) }

    it "shows credits page" do
      sign_in user
      get "/credits"
      expect(response.body).to include("You have")
    end

    it "shows credits page if user belongs to an org" do
      org = org_member.organizations.first
      sign_in org_member
      get "/credits"
      expect(response.body).to include("You have")
      expect(response.body).not_to include(CGI.escapeHTML(org.name))
    end

    it "shows credits page if user belongs to an org and is org admin" do
      org = org_admin.organizations.first
      sign_in org_admin
      get "/credits"
      expect(response.body).to include(CGI.escapeHTML(org.name))
    end

    context "when the user has made purchases that will appear in the ledger" do
      let(:params) { { spent: true, spent_at: Time.current } }

      it "shows unattributed purchases" do
        purchase_params = { user: user }
        create(:credit, params.merge(purchase_params))

        sign_in user
        get credits_path

        expect(response.body).to include("Purchase history")
        expect(response.body).to include("Miscellaneous items")
      end
    end
  end

  describe "POST /credits/create_order" do
    let(:user) { create(:user) }
    let(:razorpay_key_id) { "rzp_test_key123" }
    let(:razorpay_key_secret) { "rzp_test_secret456" }

    def razorpay_response(success:, body:)
      response_class = Class.new do
        def initialize(success, body)
          @success = success
          @body = body
        end

        attr_reader :body

        def success?
          @success
        end

        def parsed_response
          JSON.parse(body)
        end
      end

      response_class.new(success, body.to_json)
    end

    before do
      allow(Settings::General).to receive(:razorpay_key_id).and_return(razorpay_key_id)
      allow(Settings::General).to receive(:razorpay_key_secret).and_return(razorpay_key_secret)
      sign_in user
    end

    it "creates a Razorpay order and returns JSON" do
      allow(HTTParty).to receive(:post).and_return(
        razorpay_response(success: true, body: { "id" => "order_test123" }),
        )

      post create_order_credits_path, params: { credits_count: 25 }, as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["order_id"]).to eq("order_test123")
      expect(json["razorpay_key_id"]).to eq(razorpay_key_id)
    end

    it "returns error for invalid credits count" do
      post create_order_credits_path, params: { credits_count: 0 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("valid number")
    end
  end

  describe "POST /credits" do
    let(:user) { create(:user) }
    let(:razorpay_key_secret) { "rzp_test_secret456" }
    let(:order_id) { "order_test123" }
    let(:payment_id) { "pay_test456" }
    let(:valid_signature) do
      OpenSSL::HMAC.hexdigest("SHA256", razorpay_key_secret, "#{order_id}|#{payment_id}")
    end

    before do
      allow(Settings::General).to receive(:razorpay_key_id).and_return("rzp_test_key123")
      allow(Settings::General).to receive(:razorpay_key_secret).and_return(razorpay_key_secret)
      sign_in user
    end

    it "creates unspent credits on valid payment" do
      post "/credits", params: {
        credits_count: 25,
        razorpay_payment_id: payment_id,
        razorpay_order_id: order_id,
        razorpay_signature: valid_signature,
      }
      expect(user.credits.where(spent: false).size).to eq(25)
    end

    it "redirects with success notice" do
      post "/credits", params: {
        credits_count: 20,
        razorpay_payment_id: payment_id,
        razorpay_order_id: order_id,
        razorpay_signature: valid_signature,
      }
      expect(response).to redirect_to(credits_path)
      expect(flash[:notice]).to include("20")
    end

    context "when purchasing as an organization" do
      let(:org_admin) { create(:user, :org_admin) }
      let(:admin_org_id) { org_admin.organizations.first.id }

      before { sign_in org_admin }

      it "creates unspent credits for the organization" do
        post "/credits", params: {
          organization_id: admin_org_id,
          credits_count: 20,
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: valid_signature,
        }
        expect(Credit.where(organization_id: admin_org_id, spent: false).size).to eq(20)
      end

      it "does not create unspent credits for the current_user" do
        post "/credits", params: {
          organization_id: admin_org_id,
          credits_count: 20,
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: valid_signature,
        }
        expect(org_admin.credits.where(spent: false).size).to eq(0)
      end
    end

    context "when payment verification fails" do
      it "does not reward credits" do
        post "/credits", params: {
          credits_count: 25,
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: "invalid_signature",
        }
        expect(user.credits.where(spent: false).size).to eq(0)
        expect(flash[:error]).to include("verification failed")
      end
    end
  end
end
