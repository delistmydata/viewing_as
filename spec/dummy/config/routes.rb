Rails.application.routes.draw do
  resource :session
  resource :account, only: %i[ show update ] do
    # A GET that writes: the thing the :database layer exists to catch.
    get :touch
  end
  root "accounts#show"

  # Viewing an account as its owner. No id on the stop route: the cookie
  # already knows who, which is what lets the banner offer it from any page.
  post "impersonations/:id", to: "impersonations#create", as: :impersonation
  delete "impersonation", to: "impersonations#destroy", as: :stop_impersonation

  # Dummy-only: the per-session override, which a real host would decide on
  # in its own controller.
  post "impersonations/:id/writable", to: "writable_impersonations#create", as: :writable_impersonation
end
