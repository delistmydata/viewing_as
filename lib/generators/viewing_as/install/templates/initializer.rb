# Viewing an account as its owner. The lambdas below are the policy; the
# library is the mechanism. Every default here matches the Rails 8
# authentication generator; change what does not match your app.
ViewingAs.configure do |c|
  # How long a viewing session lasts. Absolute, enforced server-side, logged
  # when it runs out.
  c.timeout = 30.minutes

  # Who may view other accounts. The default asks the signed-in user `admin?`;
  # the generator's User has no such column, so add one or answer some other way.
  # c.may_impersonate = ->(user) { user.admin? }

  # Whether a given account may be viewed, by whom. Return true, or a String
  # saying why not; the String is logged as a refusal and shown to the admin.
  # Checked again on every request, so a "no" ends a running session at once.
  # This is where the account owner's consent belongs.
  # c.may_be_viewed = lambda do |target, admin|
  #   if target.admin? then "That account is an administrator."
  #   elsif target.declined_review? then "That customer has withdrawn permission."
  #   else true
  #   end
  # end

  # Read-only by default: no non-GET requests, and no ActiveRecord writes,
  # while viewing. A controller may start a writable session with
  # impersonate(user, read_only: false); the log records which kind it was.
  c.read_only = true

  # Which read-only guards run: :policy (refuse non-GET) and :database
  # (ActiveRecord::Base.while_preventing_writes). Drop :database only if a
  # viewed GET genuinely has to write, and you accept what that means.
  c.read_only_layers = %i[ policy database ]

  # Where events go. The default table is viewing_as_events (see the migration).
  # Point this at your own model if you already keep a log; it must respond to
  # record!(admin:, user:, kind:, request:, detail:).
  # c.event_model = "AdminAccessEvent"

  # Page-view rows within this window collapse into one. Start, stop, expiry,
  # revocation and refusal rows never do.
  c.dedupe_window = 15.minutes

  # How to name a person in the banner and the log.
  # c.display = ->(user) { user.email_address }

  # Advanced: who is signed in, and what binds the cookie to their sign-in.
  # The defaults read the generator's Current.session.
  # c.true_user = ->(controller) { Current.session&.user }
  # c.session_id = ->(controller) { Current.session&.id }
  # c.find_target = ->(id) { User.find_by(id: id) }
end
