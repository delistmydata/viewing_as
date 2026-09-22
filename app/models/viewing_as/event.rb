module ViewingAs
  # One record of someone on the team looking at an account through a viewing
  # session. The account owner reads their own rows, which is what makes this
  # a control rather than a promise.
  #
  # These rows live in the same database as everything else, so they bound
  # what the application permits, not what a person with a console can do.
  # Say that out loud wherever you describe the log to your users.
  class Event < ActiveRecord::Base
    self.table_name = "viewing_as_events"

    # Optional, because the row has to outlive the account it names. #reviewer
    # is what views should read; the association is a convenience on top of
    # the address, not the source of it.
    belongs_to :admin_user, class_name: ViewingAs.config.user_class, optional: true
    belongs_to :user, class_name: ViewingAs.config.user_class

    validates :kind, inclusion: { in: Kinds::ALL }

    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    # A log an admin can edit is not a log. Binds ActiveRecord only.
    def readonly?
      persisted?
    end

    def description
      Kinds::DESCRIPTIONS.fetch(kind) { kind.humanize }
    end

    # Who looked, as recorded at the time. Survives the account being deleted,
    # which is the whole reason the column exists.
    def reviewer
      admin_email.presence ||
        (admin_user && ViewingAs.config.display.call(admin_user)) ||
        "a former team member"
    end

    # Writes one row, or doesn't, and never raises in the middle of a page.
    #
    # Returns the row, or nil when it was deduped away. Callers use it for its
    # effect; nothing branches on the return.
    def self.record!(admin:, user:, kind:, request: nil, detail: nil)
      return nil if admin.nil? || user.nil?

      kind = kind.to_s
      return nil if deduped?(admin, user, kind, detail)

      create!(admin_user: admin, admin_email: ViewingAs.config.display.call(admin),
              user: user, kind: kind, detail: detail,
              ip_address: request&.remote_ip,
              user_agent: request&.user_agent&.to_s&.truncate(255))
    rescue ActiveRecord::ActiveRecordError => e
      # An audit row failing must not take down the page it was auditing. Loud
      # in the log, silent on the screen.
      logger.error("[ViewingAs::Event] could not record #{kind}: #{e.class}: #{e.message}")
      nil
    end

    # One row per admin, per account, per kind, per detail, per window. Keyed
    # on the detail too, or ten distinct reads of one kind inside a window
    # would write one row naming the first and say nothing about the rest.
    #
    # No unique index behind this: two concurrent requests can both pass and
    # write a pair of rows, which in an append-only log is harmless.
    def self.deduped?(admin, user, kind, detail)
      return false if Kinds::DISCRETE.include?(kind)

      where(admin_user_id: admin.id, user_id: user.id, kind: kind, detail: detail,
            created_at: ViewingAs.config.dedupe_window.ago..).exists?
    end
    private_class_method :deduped?
  end
end
