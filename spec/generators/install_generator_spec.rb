require "generators/viewing_as/install/install_generator"
require "tmpdir"
require "fileutils"

RSpec.describe ViewingAs::Generators::InstallGenerator do
  let(:root) { Dir.mktmpdir("viewing_as") }

  after { FileUtils.remove_entry(root) }

  def write(path, content)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def read(path) = File.read(File.join(root, path))

  def run_generator(args = [])
    described_class.start(args + [ "--quiet" ], destination_root: root)
  end

  # What `rails new` + the authentication generator leave behind.
  before do
    write "config/routes.rb", "Rails.application.routes.draw do\n  root \"home#index\"\nend\n"
    write "app/controllers/application_controller.rb",
          "class ApplicationController < ActionController::Base\n  include Authentication\nend\n"
    write "app/models/current.rb",
          "class Current < ActiveSupport::CurrentAttributes\n  attribute :session\n  delegate :user, to: :session\nend\n"
    write "app/views/layouts/application.html.erb", "<html>\n  <body>\n    <%= yield %>\n  </body>\n</html>\n"
  end

  it "installs everything, after Authentication and inside Current" do
    run_generator

    expect(read("app/controllers/application_controller.rb"))
      .to eq("class ApplicationController < ActionController::Base\n  include Authentication\n  include ViewingAs::Controller\nend\n")
    expect(read("app/models/current.rb")).to include("prepend ViewingAs::CurrentUser")
    expect(read("config/routes.rb")).to include('post "impersonations/:id"').and include('delete "impersonation"')
    expect(read("app/views/layouts/application.html.erb")).to include("<body>\n    <%= render \"viewing_as/banner\" %>\n")
    expect(read("config/initializers/viewing_as.rb")).to include("ViewingAs.configure")
    expect(read("app/controllers/impersonations_controller.rb")).to include("class ImpersonationsController")
    expect(Dir[File.join(root, "db/migrate/*_create_viewing_as_events.rb")].size).to eq(1)
  end

  it "writes a migration that names the users table" do
    run_generator

    expect(File.read(Dir[File.join(root, "db/migrate/*.rb")].sole)).to include("to_table: :users")
  end

  it "can skip the migration for a host that keeps its own log" do
    run_generator([ "--skip-migration" ])

    expect(Dir[File.join(root, "db/migrate/*")]).to be_empty
  end

  it "is idempotent" do
    2.times { run_generator }

    expect(read("app/controllers/application_controller.rb").scan("ViewingAs::Controller").size).to eq(1)
    expect(read("app/models/current.rb").scan("ViewingAs::CurrentUser").size).to eq(1)
    expect(read("app/views/layouts/application.html.erb").scan("viewing_as/banner").size).to eq(1)
  end

  it "creates Current when the host has none" do
    FileUtils.rm(File.join(root, "app/models/current.rb"))

    run_generator

    expect(read("app/models/current.rb")).to include("prepend ViewingAs::CurrentUser").and include("attribute :session")
  end
end
