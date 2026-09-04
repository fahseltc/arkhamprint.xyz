class HomeController < ApplicationController
  def index
    scenarios = ArkhamDbHelper.scenarios_index
    @campaigns = scenarios.fetch("campaigns", []).sort_by { |c| c["release_order"] || Float::INFINITY }
  end
end
