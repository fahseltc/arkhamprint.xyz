class HomeController < ApplicationController
  def index
    scenarios_path = Rails.root.join("scenarios.json")
    scenarios = JSON.parse(File.read(scenarios_path))
    @campaigns = scenarios.fetch("campaigns", []).sort_by { |c| c["release_order"] || Float::INFINITY }
  end
end
