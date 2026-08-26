class HomeController < ApplicationController
  def index
    scenarios_path = Rails.root.join("scenarios.json")
    scenarios = JSON.parse(File.read(scenarios_path))
    @campaigns = scenarios.fetch("campaigns", [])
  end
end
