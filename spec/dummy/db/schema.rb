ActiveRecord::Schema.define(version: 1) do
  create_table :users, force: true do |t|
    t.string :email_address, null: false
    t.string :password_digest, null: false
    t.string :name
    t.boolean :admin, null: false, default: false
    t.boolean :reviewable, null: false, default: true
    t.timestamps
  end
  add_index :users, :email_address, unique: true

  create_table :sessions, force: true do |t|
    t.references :user, null: false
    t.string :ip_address
    t.string :user_agent
    t.timestamps
  end

  create_table :viewing_as_events, force: true do |t|
    t.references :admin_user
    t.string :admin_email
    t.references :user, null: false
    t.string :kind, null: false
    t.string :detail
    t.string :ip_address
    t.string :user_agent
    t.datetime :created_at, null: false
  end
  add_index :viewing_as_events, [ :admin_user_id, :user_id, :kind, :created_at ],
            name: "index_viewing_as_events_on_dedupe"
  add_index :viewing_as_events, [ :user_id, :created_at ]
end
