# Viewing an account as its owner. The properties that matter are all negative
# ones (what it cannot do, and how fast it stops being able to), so most of
# this file is about refusals.
RSpec.describe "Impersonation", type: :request do
  let(:admin) { create_admin }
  let(:customer) { create_user(email_address: "customer@example.com", name: "Customer") }

  describe "starting" do
    before { sign_in admin }

    it "renders the customer's account rather than the admin's" do
      impersonate customer
      get "/account"

      expect(response.body).to match(%r{<dt>Email</dt>\s*<dd>customer@example\.com</dd>})
      expect(response.body).to include("viewing-as-banner")
    end

    it "creates no session for the customer" do
      expect { impersonate customer }.not_to change { customer.sessions.count }
    end

    it "leaves the admin's own session untouched" do
      admin_session_id = signed_in_session.id

      impersonate customer
      get "/account"

      expect(signed_in_session.id).to eq(admin_session_id)
    end

    it "shows the banner on a page that skips authentication too" do
      impersonate customer

      get "/session/new"

      expect(response.body).to include("viewing-as-banner")
    end

    it "says the session is read-only and when it ends" do
      impersonate customer
      get "/account"

      expect(response.body).to include("Nothing you do here can change their account")
      expect(response.body).to match(/Ends in (30|29) minutes/)
    end

    it "shows no banner to an admin who is not viewing anyone" do
      get "/account"

      expect(response.body).not_to include("viewing-as-banner")
    end

    it "sends no-store while viewing" do
      impersonate customer

      get "/account"

      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "logs the start" do
      impersonate customer

      event = events(ViewingAs::Kinds::START, user: customer).sole
      expect(event.admin_user).to eq(admin)
      expect(event.admin_email).to eq("admin@example.com")
      expect(event.detail).to be_nil
      expect(event.ip_address).to be_present
    end

    it "collapses many viewed page loads into one row" do
      impersonate customer
      3.times { get "/account" }

      expect(events(ViewingAs::Kinds::READ, user: customer).count).to eq(1)
    end
  end

  describe "refusing to start" do
    let(:other_admin) { create_admin(email_address: "second@example.com") }

    before { sign_in admin }

    it "refuses another administrator" do
      impersonate other_admin

      expect(flash[:alert]).to eq("That account is an administrator.")
      get "/account"
      expect(response.body).to include("admin@example.com")
    end

    it "refuses yourself" do
      impersonate admin

      expect(flash[:alert]).to include("your own account")
    end

    it "refuses a customer who has withdrawn permission, and logs the refusal" do
      customer.update!(reviewable: false)

      impersonate customer

      expect(flash[:alert]).to include("withdrawn permission")
      expect(events(ViewingAs::Kinds::REFUSED, user: customer).sole.detail).to include("withdrawn")
    end

    it "404s for an account that does not exist" do
      post "/impersonations/0"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "refusing to start, as somebody who is not an admin" do
    it "404s for a signed-in customer" do
      sign_in create_user(email_address: "nosy@example.com")

      impersonate customer

      expect(response).to have_http_status(:not_found)
    end

    it "404s for a signed-out visitor" do
      impersonate customer

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "read-only" do
    before do
      sign_in admin
      impersonate customer
    end

    it "refuses a profile update" do
      patch "/account", params: { user: { name: "Mallory" } }

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.name).to eq("Customer")
    end

    it "refuses signing out" do
      delete "/session"

      expect(response).to have_http_status(:forbidden)
      expect(signed_in_session).to be_present
    end

    it "cannot smuggle a write past the guard with _method" do
      post "/account", params: { _method: "patch", user: { name: "Mallory" } }

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.name).to eq("Customer")
    end

    it "refuses a GET that writes, and changes nothing" do
      get "/account/touch"

      expect(response).to have_http_status(:forbidden)
      expect(customer.reload.name).to eq("Customer")
    end

    it "writes nothing to any table but the log" do
      written = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql]
        written << sql if sql.match?(/\A\s*(INSERT|UPDATE|DELETE)/i) && !sql.include?("viewing_as_events")
      end

      get "/account"

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(written).to be_empty
    end
  end

  describe "ending" do
    before do
      sign_in admin
      impersonate customer
    end

    it "allows the stop action through the write guard, and logs it" do
      delete "/impersonation"

      expect(response).to redirect_to("/")
      expect(events(ViewingAs::Kinds::STOP, user: customer)).to exist
    end

    it "returns the admin to their own account on the same session" do
      admin_session_id = signed_in_session.id

      delete "/impersonation"
      get "/account"

      expect(response.body).to include("admin@example.com")
      expect(signed_in_session.id).to eq(admin_session_id)
    end

    it "expires on its own after the timeout, and says so in the log" do
      travel_to(ViewingAs.config.timeout.from_now + 1.minute) do
        get "/account"

        expect(response.body).to include("admin@example.com")
        expect(response.body).not_to include("viewing-as-banner")
      end
      expect(events(ViewingAs::Kinds::EXPIRED, user: customer)).to exist
    end

    it "drops on the next request once the customer withdraws permission" do
      customer.update!(reviewable: false)

      get "/account"

      expect(response.body).to include("admin@example.com")
      expect(events(ViewingAs::Kinds::REVOKED, user: customer)).to exist
    end

    it "drops once the admin flag is revoked" do
      admin.update!(admin: false)

      get "/account"

      expect(response.body).to include("admin@example.com")
    end

    it "drops once the admin's session is destroyed elsewhere" do
      admin.sessions.destroy_all

      get "/account"

      expect(response).to redirect_to("/session/new")
    end

    # Without this the chain simply carries on once the session ends
    # mid-request: the write guard sees nothing being viewed and waves the
    # request through, and the acting user has become the admin. The click
    # lands on the ADMIN's own account.
    %w[ expiry withdrawal ].each do |ending|
      it "refuses a write that lands after the session ends by #{ending}" do
        if ending == "expiry"
          travel_to(ViewingAs.config.timeout.from_now + 1.minute) do
            patch "/account", params: { user: { name: "Mallory" } }
          end
        else
          customer.update!(reviewable: false)
          patch "/account", params: { user: { name: "Mallory" } }
        end

        expect(response).to have_http_status(:conflict)
        expect(admin.reload.name).to be_nil
        expect(customer.reload.name).to eq("Customer")
      end
    end
  end

  describe "cross-site requests" do
    it "does not start viewing from a request with no token" do
      sign_in admin

      with_forgery_protection do
        begin
          impersonate customer
        rescue ActionController::InvalidAuthenticityToken
          # Either strategy is a refusal; what matters is what did not happen.
        end
      end

      get "/account"
      expect(response.body).to include("admin@example.com")
      expect(events(ViewingAs::Kinds::START, user: customer)).not_to exist
    end
  end

  describe "the cookie itself" do
    it "ignores one minted under a different admin session" do
      sign_in admin
      impersonate customer
      stale = cookies[ViewingAs.config.cookie_name.to_s]

      delete "/impersonation"
      delete "/session"
      sign_in admin
      cookies[ViewingAs.config.cookie_name.to_s] = stale

      get "/account"

      expect(response.body).to include("admin@example.com")
      expect(response.body).not_to include("viewing-as-banner")
      expect(events(ViewingAs::Kinds::REVOKED, user: customer)).to exist
    end

    # The admin's session died elsewhere and they are signing back in while the
    # browser still holds the old cookie. The sign-in is their own write, not a
    # click aimed at the customer, so it goes through.
    it "does not refuse a sign-in made while holding a dead cookie" do
      sign_in admin
      impersonate customer
      admin.sessions.destroy_all

      sign_in admin

      expect(response).to redirect_to("/")
      expect(signed_in_session).to be_present
    end

    it "ignores a tampered signature" do
      sign_in admin
      cookies[ViewingAs.config.cookie_name.to_s] = "not-a-signed-value"

      get "/account"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("admin@example.com")
    end

    it "is not the Rails session" do
      sign_in admin
      impersonate customer

      expect(session.to_hash.keys).not_to include(a_string_matching(/impersonat/))
      expect(cookies[ViewingAs.config.cookie_name.to_s]).to be_present
    end
  end
end
