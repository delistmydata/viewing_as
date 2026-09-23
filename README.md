# viewing_as

A Rails impersonation gem for the case where somebody's data is on the other side of the button.

An administrator opens a customer's account and sees the site exactly as that customer sees it. By default they can change nothing: every write is refused, twice over. The customer can withdraw permission and it takes effect on the admin's next click. Every session is time-boxed, and every one of them is logged in words the customer can read on their own account page.

Built for the Rails 8 authentication generator. It also works with Devise or any hand-rolled sign-in, because everything it needs to know about your app is a handful of lambdas in an initializer.

[![Gem Version](https://badge.fury.io/rb/viewing_as.svg)](https://rubygems.org/gems/viewing_as) [![CI](https://github.com/delistmydata/viewing_as/actions/workflows/ci.yml/badge.svg)](https://github.com/delistmydata/viewing_as/actions)

## Why not pretender?

[pretender](https://github.com/ankane/pretender) is fifty lines that swap `current_user`. If your support team needs to "log in as a user" and you trust them completely, use it. It's excellent at what it does.

This gem is for when you can't rely on trust alone. We built it for a data removal service, where the accounts hold home addresses and phone numbers and an admin who could act as a customer could start scans or withdraw the authorizations we file removals under. The customer had to be able to say no, and had to be able to see that anyone looked.

| | viewing_as | pretender | devise_masquerade | switch_user |
|---|---|---|---|---|
| Read-only while impersonating | default, two layers | no | no | no |
| Writable sessions | per-session opt-in | always | always | always |
| Re-checks permission on every request | yes | signed-in only | no | no |
| Server-side timeout | yes, logged | no | link expiry only | no |
| Audit log the user can read | yes | no | no | no |
| Consent hook | yes | no | no | `controller_guard` |
| Refuses a write that lands after the session ends | yes, 409 | no | no | no |
| Where state lives | signed cookie | `session[]` | session or cache | `session[]` |
| Works with | Rails 8 generator, Devise, anything | anything | Devise only | Devise, Sorcery, others |

## Install

```ruby
# Gemfile
gem "viewing_as"
```

```sh
bin/rails generate viewing_as:install
bin/rails db:migrate
```

The generator writes three files, adds two routes, and edits three files:

| Writes | Edits |
|---|---|
| `config/initializers/viewing_as.rb` (the policy) | `ApplicationController`: includes `ViewingAs::Controller` after `Authentication` |
| `db/migrate/…_create_viewing_as_events.rb` (the log) | `app/models/current.rb`: prepends `ViewingAs::CurrentUser` |
| `app/controllers/impersonations_controller.rb` | `app/views/layouts/application.html.erb`: renders the banner |

Run it twice and it skips what it already did. Pass `--skip-migration` if you'll keep your own log (see [Keeping one log](#keeping-one-log)).

Then put a button where an admin can reach it:

```erb
<%= button_to "View as #{user.email_address}", impersonation_path(user), method: :post %>
```

The Rails 8 generator's `User` has no `admin` column. Add one, or tell the initializer another way to decide:

```ruby
ViewingAs.configure do |c|
  c.may_impersonate = ->(user) { user.admin? }
end
```

That is enough for a working, read-only, logged, 30-minute impersonation with a banner.

## Read-only is the default. You can turn it off.

Out of the box a viewing session cannot change anything. Two guards enforce it:

1. **The policy.** Any request that isn't GET or HEAD gets a 403 before the action runs. The method is read off the Rack env, which is the same value the router used, so `_method=get` on a POST can't get a write action through.
2. **The guarantee.** The action runs inside `ActiveRecord::Base.while_preventing_writes`. This catches what the policy can't see: an `update_column` in a helper, a counter cache, a touch-on-read somebody adds next year. A write that reaches this guard is logged at error level, because it's a bug rather than a user action.

Both are settings, and there are three ways to loosen them.

### Make every session writable

A support team that fixes addresses as the customer gets the same log, the same timeout and the same revocation, with writes allowed:

```ruby
ViewingAs.configure do |c|
  c.read_only = false
end
```

### Make one session writable

Keep the default read-only and let a controller ask for a writable session when it has a reason to. The choice is sealed into the signed cookie when the session starts, so nothing in the browser can flip it later, and the start row in the log says `writable`:

```ruby
class ImpersonationsController < ApplicationController
  def create
    target = User.find(params[:id])
    attempt = impersonate(target, read_only: params[:mode] != "edit")

    if attempt.started?
      redirect_to root_path, notice: "Viewing as #{target.email_address}."
    else
      redirect_back_or_to root_path, alert: attempt.reason
    end
  end
end
```

Who may ask for a writable session is your decision, made in that controller. The gem doesn't have an opinion.

### Keep one guard and drop the other

If a viewed GET genuinely has to write something, say a "last seen" stamp you can't move, drop the database guard and keep the policy:

```ruby
ViewingAs.configure do |c|
  c.read_only_layers = [ :policy ]     # default: %i[ policy database ]
end
```

The banner reads differently in each mode. Read-only: "Nothing you do here can change their account, and they can see a record of this visit." Writable: "Everything you do here is done as them, and they can see a record of this visit."

## Deciding who may view whom

`may_be_viewed` is asked when a session starts and again on every request while it lasts. Return `true`, or a String saying why not. The String is shown to the admin and written to the log as a refusal. Once a session is running, a String ends it on the next request and logs that as a revocation.

This is where consent goes. Ours checks a column the customer flips from their account page:

```ruby
ViewingAs.configure do |c|
  c.may_be_viewed = lambda do |target, admin|
    if target.admin? then "That account is an administrator."
    elsif target.declined_review? then "That customer has withdrawn permission for review."
    else true
    end
  end
end
```

Some other shapes it takes:

```ruby
# Support staff may view customers on their own team only
c.may_be_viewed = ->(target, admin) { target.team_id == admin.team_id || "Not your team." }

# Only during an open support ticket
c.may_be_viewed = ->(target, _admin) { target.tickets.open.any? || "No open ticket." }

# Nobody views an account whose owner has asked for deletion
c.may_be_viewed = ->(target, _admin) { target.deletion_requested_at.nil? || "That account is closing." }
```

The lambda may take one argument or two. Self-impersonation is refused before it's called.

`may_impersonate` decides who may view accounts at all. It's checked on every request too, so revoking someone's admin flag ends any session they're holding:

```ruby
c.may_impersonate = ->(user) { user.admin? && user.active? }
c.may_impersonate = ->(user) { user.has_role?(:support) }
```

## In controllers and views

Every controller that includes `ViewingAs::Controller` gets these, and they're all helper methods too:

```ruby
true_user                  # who is actually here: use it for every permission check and every log row
impersonated_user          # who the request acts as, or nil
impersonating?
impersonation_read_only?
impersonation_expires_at
```

`Current.user` answers with the viewed account while a session is on. That's what lets the rest of your app work unmodified: every controller that reads `Current.user` renders the customer's data without knowing anything changed.

Two places that must **not** use `Current.user`:

```ruby
# Authorization. The admin is here; the customer is not.
class ScansController < ApplicationController
  def create
    head :forbidden unless true_user.can_start_scans?   # not Current.user
    ...
  end
end

# Your own audit trail, if you keep one apart from this gem's.
Audited.current_user_method = :true_user
```

An admin area should refuse to render while a session is on. Otherwise every `Current.user` on every admin page would be the customer, including the ones deciding what to show:

```ruby
class Admin::BaseController < ApplicationController
  before_action :refuse_while_impersonating

  private

  def refuse_while_impersonating
    redirect_to root_path, alert: "Stop viewing that account first." if impersonating?
  end
end
```

In a view, hide what the admin can't use:

```erb
<% if impersonating? %>
  <p>Signing out isn't available while viewing this account. Use "Stop viewing".</p>
<% else %>
  <%= button_to "Sign out", session_path, method: :delete %>
<% end %>
```

### Stopping

The stop action is the one write the read-only guards must let through, because it's the way out. The generated controller skips them on `destroy` and nowhere else:

```ruby
class ImpersonationsController < ApplicationController
  skip_before_action :refuse_writes_while_impersonating, only: :destroy
  skip_around_action :read_only_while_impersonating, only: :destroy

  def destroy
    end_impersonation!
    redirect_to root_path, notice: "Stopped viewing that account.", status: :see_other
  end
end
```

The stop route has no id in it. The cookie already knows who, which is what lets the banner offer "Stop viewing" from any page on the site.

### The banner

`app/views/viewing_as/_banner.html.erb` is rendered from your layout, gates itself on `impersonating?`, and ships unstyled with the classes `viewing-as-banner`, `viewing-as-banner__text` and `viewing-as-banner__stop`. Copy it into your own `app/views/viewing_as/` to change the words. If your stop route is named differently, pass it in:

```erb
<%= render "viewing_as/banner", stop_path: admin_stop_impersonation_path %>
```

## The log

Every session writes rows to `viewing_as_events`, each with a `kind`, the admin's address as it was at the time, the target, the request's IP and user agent, and an optional `detail`. The kinds:

| kind | when |
|---|---|
| `impersonation_start` | a session began (`detail` is `writable` for a writable one) |
| `impersonated_read` | a page was viewed. Collapsed to one row per admin, per account, per 15 minutes |
| `impersonation_stop` | the admin clicked stop |
| `impersonation_expired` | the timeout ran out |
| `impersonation_revoked` | `may_be_viewed` or `may_impersonate` said no, or the admin's session ended |
| `impersonation_refused` | a session was asked for and refused (`detail` is the reason) |

Page views collapse because a listings page with a screenshot per match would otherwise write hundreds of rows saying one thing, and a log nobody can read is as good as no log. The lifecycle rows never collapse.

Show the customer their own rows:

```ruby
# app/controllers/accounts_controller.rb
@access_events = ViewingAs::Event.where(user: Current.user).newest_first
```

```erb
<% @access_events.each do |event| %>
  <li>
    <%= event.description %>            <%# "Started viewing your account as you see it" %>
    by <%= event.reviewer %>            <%# the admin's address, even after their account is gone %>
    <%= time_ago_in_words(event.created_at) %> ago
    <% if event.detail.present? %>(<%= event.detail %>)<% end %>
  </li>
<% end %>
```

Rows can't be edited through ActiveRecord once written (`readonly?` is true when persisted), and a row failing to write never takes down the page it was recording. They do live in the same database as everything else, so they bound what the application permits, not what a person with a console can do. Say that wherever you describe the log to your users.

### Keeping one log

If you already have an audit table, point the gem at it and skip the migration. Your model needs one class method:

```ruby
ViewingAs.configure do |c|
  c.event_model = "AdminAccessEvent"
end

class AdminAccessEvent < ApplicationRecord
  def self.record!(admin:, user:, kind:, request: nil, detail: nil)
    # kind is one of the strings in ViewingAs::Kinds
    create!(admin_user: admin, user: user, kind: kind, detail: detail, ip_address: request&.remote_ip)
  end
end
```

`ViewingAs::Kinds::DESCRIPTIONS` has the customer-facing wording for each kind if you want to reuse it.

## Every setting

```ruby
ViewingAs.configure do |c|
  c.timeout = 30.minutes                       # absolute, from the moment a session starts
  c.cookie_name = :impersonation
  c.read_only = true
  c.read_only_layers = %i[ policy database ]
  c.no_store = true                            # Cache-Control: no-store on every viewed response
  c.dedupe_window = 15.minutes                 # for impersonated_read rows
  c.event_model = "ViewingAs::Event"
  c.user_class = "User"
  c.display = ->(user) { user.email_address }  # how a person is named in the banner and the log

  c.may_impersonate = ->(user) { user.admin? }
  c.may_be_viewed = ->(target, admin) { true }

  # Who is signed in, and what binds the cookie to their sign-in. These
  # defaults are the Rails 8 generator's shapes.
  c.true_user = ->(controller) { Current.session&.user }
  c.session_id = ->(controller) { Current.session&.id }
  c.resume_session = ->(controller) { controller.send(:resume_session) }
  c.find_target = ->(id) { User.find_by(id: id) }
end
```

### With Devise

```ruby
ViewingAs.configure do |c|
  c.true_user = ->(controller) { controller.send(:warden).user }
  c.session_id = ->(controller) { controller.session.id.to_s }
  c.resume_session = ->(_controller) {}
end
```

```ruby
class Current < ActiveSupport::CurrentAttributes
  prepend ViewingAs::CurrentUser
  attribute :user
end

class ApplicationController < ActionController::Base
  before_action { Current.user = current_user }   # Devise's current_user: the admin
  include ViewingAs::Controller
end
```

`Current.user` then answers with the viewed account during a session and with Devise's user otherwise. Devise's own `current_user` keeps meaning the admin, which is what you want for authorization.

## Action Cable

A channel connection identifies itself by the session's user and has nothing the read-only guard can wrap. A channel opened while an admin is viewing an account would run as the admin, with the admin's reach, from a page rendered as the customer. Refuse it:

```ruby
class ApplicationCable::Connection < ActionCable::Connection::Base
  include ViewingAs::Cable
  identified_by :current_user

  def connect
    reject_unauthorized_connection if viewing_another_account?
    self.current_user = find_verified_user
  end
end
```

## How it works

The state is a signed cookie holding the target's id, the admin's own session id, a start timestamp and the read-only flag. Nothing in it is trusted. On every request the gem reloads the sign-in, then checks that the admin still passes `may_impersonate`, that the admin's session id still matches the cookie, that the target still exists, and that `may_be_viewed` still says yes. Any failure ends the session and logs why.

The timeout is enforced from the start timestamp, server-side. The cookie deliberately has no `expires`: a cookie that vanished from the browser first would never be seen by the server, so the expiry would never reach the log, and the customer would see a session that started and apparently never ended.

If a session ends on a request that was going to write, the response is 409 and nothing happens. Without this the filter chain carries on with nobody being viewed, the write guard waves the request through, and the acting user has quietly become the admin. In our app the routes that matter are singular resources with no id in the path, so "withdraw authorization" at minute thirty-one would have withdrawn the admin's own. The 409 holds in writable sessions too. It's about whose account the click lands on.

### Why a cookie and not the session

Merely loading `session[]` makes Rack emit `Set-Cookie`, and a response carrying `Set-Cookie` can't be cached as public. Our marketing pages sit behind CloudFront and the header on every one of them checks whether you're signed in. Keeping impersonation state in the session would have quietly un-cached the whole content site to serve a feature two people use. A second signed cookie costs nothing to read and changes nothing about caching.

## What it doesn't cover

- Writes that aren't ActiveRecord. A viewed GET that enqueues a job, sends mail or writes to S3 still does. A spec asserting no job is enqueued during a viewed GET is what keeps that true in the app this came from.
- A CDN that forwards cookies on some paths and not others renders the banner only where the cookie reaches. That's also the only place the customer's data can reach, so nothing is disclosed without the banner. What's lost is the reminder while wandering the public pages.
- People with database access. The log is a control on the application, not on them.

## Requirements

Ruby 3.3 or newer. Rails 7.2, 8.0 and 8.1 are on CI.

## Development

```sh
bundle install
bundle exec rspec
```

The specs run against `spec/dummy`, a Rails app with the authentication generator's output and this gem's install applied. Most of them are refusals, and they're the part worth reading first.

## License

MIT.
