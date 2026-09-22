# viewing_as

Let an administrator see an account as its owner sees it, without being able
to change it. Built for the Rails 8 authentication generator; works with
anything that can answer "who is signed in".

- **Read-only by default, in two layers.** Every request that is not GET or
  HEAD is refused before the action runs, and the action itself runs inside
  `ActiveRecord::Base.while_preventing_writes` for whatever the first layer
  cannot see. Both are settings; a support team that needs to fix things as
  the customer can start a writable session and get the same log.
- **Re-validated on every request.** The cookie names a target and the admin's
  own session; the database says whether the admin is still an admin, whether
  that session still exists, and whether the owner still permits it. A "no"
  from any of those ends the session on the next click, without touching
  anybody's browser.
- **Fails closed.** If the session expires or is revoked on a request that was
  going to write, the response is 409 and nothing happens. Without this the
  filter chain carries on with the admin as the acting user, and a click aimed
  at the customer's account lands on the admin's own.
- **Time-boxed.** An absolute server-side timeout, logged when it runs out.
- **Logged in words the owner can read.** "Started viewing your account as you
  see it." Refusals are logged too. Page views collapse to one row per quarter
  hour; lifecycle rows never collapse; rows outlive the admin who made them
  and cannot be edited through ActiveRecord.
- **Not the Rails session.** State lives in its own signed cookie. Merely
  loading `session[]` makes Rack emit `Set-Cookie`, which un-caches the page at
  any CDN in front of the app. Reading a second signed cookie costs nothing.

## How it compares

| | viewing_as | pretender | devise_masquerade | switch_user |
|---|---|---|---|---|
| Read-only mode | two layers, per-session override | no | no | no |
| Re-validated from the database each request | yes | signed-in check only | no | no |
| Fails closed on mid-request expiry | 409 | n/a | n/a | n/a |
| Server-side timeout | yes, logged | no | link token only | no |
| Event log | yes, owner-readable | no | no | no |
| Consent hook | yes, checked every request | no | no | `controller_guard` |
| Storage | signed cookie | `session[]` | session or cache | `session[]` |
| Auth coupling | Rails 8 generator by default; lambdas for anything else | agnostic | Devise only | Devise, Sorcery, others |

pretender is fifty lines that swap `current_user`, and if that is all you need
it is the right choice. This library is for the case where somebody's data is
on the other side of the button.

## Install

```ruby
gem "viewing_as"
```

```
bin/rails generate viewing_as:install
bin/rails db:migrate
```

The generator writes `config/initializers/viewing_as.rb`, a migration for
`viewing_as_events`, an `ImpersonationsController`, two routes, and then
edits three files: it includes `ViewingAs::Controller` in
`ApplicationController` after `include Authentication`, prepends
`ViewingAs::CurrentUser` into `Current`, and renders the banner at the top of
the layout. Each edit is skipped if already made.

Put a button somewhere an admin can reach:

```erb
<%= button_to "View as #{user.email_address}", impersonation_path(user), method: :post %>
```

The generator's `User` has no `admin` column. Add one, or tell the initializer
how else to decide:

```ruby
ViewingAs.configure do |c|
  c.may_impersonate = ->(user) { user.admin? }
end
```

## Consent, and every other decision

```ruby
ViewingAs.configure do |c|
  c.timeout = 30.minutes

  # true, or a String saying why not. Logged as a refusal when a session
  # starts; checked again on every request, so a "no" ends a running session.
  c.may_be_viewed = lambda do |target, admin|
    if target.admin? then "That account is an administrator."
    elsif target.declined_review? then "That customer has withdrawn permission."
    else true
    end
  end

  # Read-only unless a controller says impersonate(user, read_only: false).
  c.read_only = true
  c.read_only_layers = %i[ policy database ]

  # Keep one log: point at your own model instead of viewing_as_events. It
  # must respond to record!(admin:, user:, kind:, request:, detail:); the
  # kinds are the strings in ViewingAs::Kinds.
  c.event_model = "AdminAccessEvent"

  # Who is here, and what binds the cookie to their sign-in. The defaults read
  # the generator's Current.session.
  c.true_user = ->(controller) { Current.session&.user }
  c.session_id = ->(controller) { Current.session&.id }
  c.find_target = ->(id) { User.find_by(id: id) }
  c.display = ->(user) { user.email_address }
end
```

## In a controller

```ruby
attempt = impersonate(user)           # or impersonate(user, read_only: false)
attempt.started?                      # true, or false with attempt.reason
end_impersonation!                    # the way out; logs a stop row

true_user                             # who is actually here; use for every permission check
impersonated_user                     # who the request acts as, or nil
impersonating?
impersonation_read_only?
impersonation_expires_at
```

`Current.user` answers with the viewed account while a session is on, which
is what lets the rest of the app work unmodified. Anything that must know who
is really here reads `true_user`.

The stop action is the one write the read-only guards must let through. The
generated controller skips them on `destroy` and nowhere else:

```ruby
skip_before_action :refuse_writes_while_impersonating, only: :destroy
skip_around_action :read_only_while_impersonating, only: :destroy
```

An admin area should refuse to render while a session is on, or every
`Current.user` on every page would be the customer, including the ones
deciding what to render:

```ruby
before_action { redirect_to root_path, alert: "Stop viewing first." if impersonating? }
```

## Action Cable

A connection identifies itself by the session's user and has nothing the
read-only guard can wrap. Refuse it while viewing:

```ruby
class ApplicationCable::Connection < ActionCable::Connection::Base
  include ViewingAs::Cable

  def connect
    reject_unauthorized_connection if viewing_another_account?
    ...
```

## What the owner sees

`ViewingAs::Event` rows for a user, newest first, each with `description`,
`reviewer`, `detail` and `created_at`:

```ruby
ViewingAs::Event.where(user: current_user).newest_first
```

These rows live in the same database as everything else. They bound what the
application permits, not what a person with a console can do. Say so wherever
you describe the log to your users.

## What it does not cover

- Writes that are not ActiveRecord: a viewed GET that enqueues a job, sends
  mail or writes to S3 still does. A spec asserting no job is enqueued during
  a viewed GET is what keeps that true in the app this was extracted from.
- A CDN that forwards cookies on some paths and not others will render the
  banner only where the cookie reaches. That is also where the owner's data
  can reach, so nothing is disclosed without the banner; what is lost is the
  reminder while wandering the public pages.

## Development

```
bundle install
bundle exec rspec
```

The specs run against `spec/dummy`, a Rails app with the authentication
generator's output and this library's install applied.

## License

MIT.
