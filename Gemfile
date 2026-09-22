source "https://rubygems.org"

gemspec

# Local development runs against the newest Rails. The CI matrix in
# gemfiles/ pins the older ones.
gem "rails", "~> 8.1.0"
gem "sqlite3", ">= 2.1"
gem "bcrypt"
gem "rspec-rails", "~> 8.0"
gem "rubocop-rails-omakase", require: false

# json 3.0 made parse options keyword-only; Rails <= 8.1.3 still passes a Hash.
gem "json", "< 3"
