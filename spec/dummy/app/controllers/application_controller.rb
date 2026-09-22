class ApplicationController < ActionController::Base
  include Authentication
  include ViewingAs::Controller
end
