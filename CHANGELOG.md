# Changelog

## 0.1.0 (2026-09-22)

First release. Extracted from a production Rails 8.1 app, where it had run
since 2026-09 with the same request specs that ship here.

- Viewing sessions in a signed cookie, re-validated from the database on every request
- Read-only by default, in two layers, with a per-session override
- Fail-closed 409 when a write lands after the session has ended
- Absolute server-side timeout, logged as its own event
- Event log with owner-readable descriptions, deduped page views, append-only rows
- Consent hook checked at start and on every request
- Banner partial, `no-store`, Action Cable mixin
- `rails g viewing_as:install`
