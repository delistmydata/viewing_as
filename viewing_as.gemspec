require_relative "lib/viewing_as/version"

Gem::Specification.new do |spec|
  spec.name = "viewing_as"
  spec.version = ViewingAs::VERSION
  spec.authors = [ "Ed" ]
  spec.summary = "Impersonation for the Rails 8 authentication generator: read-only by default, consented, time-boxed, logged"
  spec.description = <<~DESC
    Let an administrator view an account as its owner. Read-only by default (two
    layers: no non-GET requests, and ActiveRecord writes refused), re-validated
    from the database on every request so revoked consent bites on the next click,
    time-boxed server-side, and logged in words the account owner can read.
    Stores its state in a signed cookie rather than the Rails session, so an
    edge-cached site stays cached. Built for the Rails 8 authentication
    generator; works with anything that can answer "who is signed in".
  DESC
  spec.license = "MIT"
  spec.homepage = "https://github.com/delistmydata/viewing_as"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  spec.files = Dir["lib/**/*", "app/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties", ">= 7.2"
  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "actionpack", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
end
