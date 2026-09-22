module ViewingAs
  # The event kinds, as strings, so a host that keeps its own log can store the
  # same values without loading the library's model.
  module Kinds
    # Browsed the site as them. Deduped per window by the default event model:
    # the question a log answers is "did someone look, and when", not "how many
    # requests did they issue".
    READ = "impersonated_read".freeze

    # Lifecycle. Discrete facts, never deduped: two sessions an hour apart are
    # two rows.
    START = "impersonation_start".freeze
    STOP = "impersonation_stop".freeze
    EXPIRED = "impersonation_expired".freeze
    REVOKED = "impersonation_revoked".freeze
    REFUSED = "impersonation_refused".freeze

    ALL = [ READ, START, STOP, EXPIRED, REVOKED, REFUSED ].freeze
    DISCRETE = [ START, STOP, EXPIRED, REVOKED, REFUSED ].freeze

    # Phrasing for the account owner's own view of the log. Plain on purpose:
    # the person reading it did not build this and should not have to guess
    # what "impersonated_read" was supposed to mean.
    DESCRIPTIONS = {
      READ => "Viewed your pages as you see them",
      START => "Started viewing your account as you see it",
      STOP => "Stopped viewing your account",
      EXPIRED => "Stopped viewing your account (time limit reached)",
      REVOKED => "Stopped viewing your account (permission ended)",
      REFUSED => "Tried to view your account and was refused"
    }.freeze
  end
end
