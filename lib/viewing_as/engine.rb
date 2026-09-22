module ViewingAs
  # Autoloads app/models/viewing_as/event.rb and serves the banner partial from
  # app/views/viewing_as/. No routes: the host owns the two it needs, which the
  # install generator writes.
  class Engine < ::Rails::Engine
    engine_name "viewing_as"
  end
end
