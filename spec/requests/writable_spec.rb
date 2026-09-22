# Read-only is a setting. A support team that fixes things as the customer
# wants the same log, the same leash and the same revocation, with writes.
RSpec.describe "Writable viewing sessions", type: :request do
  let(:admin) { create_admin }
  let(:customer) { create_user(email_address: "customer@example.com", name: "Customer") }

  before { sign_in admin }

  describe "with read_only off globally" do
    around { |example| with_viewing_as(read_only: false) { example.run } }

    it "lets a write through, as the customer" do
      impersonate customer
      patch "/account", params: { user: { name: "Corrected" } }

      expect(response).to redirect_to("/account")
      expect(customer.reload.name).to eq("Corrected")
      expect(admin.reload.name).to be_nil
    end

    it "says so in the banner and the log" do
      impersonate customer
      get "/account"

      expect(response.body).to include("Everything you do here is done as them")
      expect(events(ViewingAs::Kinds::START, user: customer).sole.detail).to eq("writable")
    end

    it "still refuses a write that lands after the session ends" do
      impersonate customer
      customer.update!(reviewable: false)

      patch "/account", params: { user: { name: "Mallory" } }

      expect(response).to have_http_status(:conflict)
      expect(admin.reload.name).to be_nil
    end

    it "still logs, times out and sends no-store" do
      impersonate customer
      get "/account"
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(events(ViewingAs::Kinds::READ, user: customer)).to exist

      travel_to(ViewingAs.config.timeout.from_now + 1.minute) { get "/account" }
      expect(events(ViewingAs::Kinds::EXPIRED, user: customer)).to exist
    end
  end

  describe "per-session override" do
    it "starts a writable session when the controller asks for one" do
      post "/impersonations/#{customer.id}/writable"
      patch "/account", params: { user: { name: "Corrected" } }

      expect(customer.reload.name).to eq("Corrected")
      expect(events(ViewingAs::Kinds::START, user: customer).sole.detail).to eq("writable")
    end

    it "seals the choice into the cookie, so a read-only session stays read-only after the default flips" do
      impersonate customer

      with_viewing_as(read_only: false) do
        patch "/account", params: { user: { name: "Mallory" } }
      end

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.name).to eq("Customer")
    end
  end

  describe "read_only_layers" do
    it "with :policy alone, lets a GET that writes through" do
      with_viewing_as(read_only_layers: [ :policy ]) do
        impersonate customer
        get "/account/touch"
      end

      expect(response).to redirect_to("/account")
      expect(customer.reload.name).to eq("touched")
    end

    it "with :database alone, refuses the write rather than the request" do
      with_viewing_as(read_only_layers: [ :database ]) do
        impersonate customer
        patch "/account", params: { user: { name: "Mallory" } }
      end

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.name).to eq("Customer")
    end
  end
end
