# lib/tasks/arkham_import.rake
#
# Imports scenario card data from ArkhamDB's public API and writes it in the
# format GeneratePdfFromScenarioJob expects, then registers the campaign in
# scenarios.json so it shows up in the dropdown.
#
# The importer supports both the older one-scenario-per-pack release model and
# newer campaign-expansion packs that contain multiple scenarios. For a pack
# containing multiple scenarios, set `scenario_card_name` on the scenario
# definition. The importer finds that scenario's encounter_code and uses it to
# select the matching encounter cards.
#
# Usage:
#   rake arkham:import_campaign[config/campaign_imports/circle_undone.json]
#
# Config file format (one per campaign you want to import):
# {
#   "campaign_name": "The Circle Undone",
#   "output_file": "02_the_circle_undone.json",
#   "scenarios": [
#     { "pack_code": "tsn", "title": "The Secret Name", "label": "1. The Secret Name" },
#     { "pack_code": "wos", "title": "The Wages of Sin", "label": "2. The Wages of Sin" }
#   ]
# }

namespace :arkham do
  desc "Import a campaign's scenario card data from ArkhamDB into a NN_campaign.json file, and register it in scenarios.json"
  task :import_campaign, [ :config_path ] => :environment do |_t, args|
    unless args[:config_path]
      puts "Usage: rake arkham:import_campaign[path/to/campaign_config.json]"
      exit 1
    end

    config = JSON.parse(File.read(args[:config_path]))
    campaign_name = config.fetch("campaign_name")
    output_file = config.fetch("output_file")
    scenario_defs = config.fetch("scenarios")

    missions = {}

    scenario_defs.each do |scenario_def|
      pack_code = scenario_def.fetch("pack_code")
      title = scenario_def.fetch("title")

      puts "Fetching pack '#{pack_code}' for scenario '#{title}'..."
      response = HTTParty.get("https://arkhamdb.com/api/public/cards/#{pack_code}")

      unless response.code == 200
        puts "  ! Failed to fetch pack '#{pack_code}' (HTTP #{response.code}), skipping"
        next
      end

      cards = JSON.parse(response.body)

      # Newer campaign-expansion packs contain several scenarios in one pack.
      # ArkhamDB associates cards with an encounter_code, and the scenario card
      # itself provides the code we need to isolate one scenario.
      scenario_card_name = scenario_def["scenario_card_name"] || title
      if title == "Non-Scenario Encounters"
        cards = cards.select { |c| c["encounter_code"].nil? }
      elsif scenario_def["scenario_card_name"] || cards.count { |c| c["name"] == title && c["type_code"] == "scenario" } == 1
        scenario_card = cards.find { |c| c["name"] == scenario_card_name && c["type_code"] == "scenario" }
        if scenario_card && scenario_card["encounter_code"]
          encounter_code = scenario_card["encounter_code"]
          cards = cards.select { |c| c["encounter_code"] == encounter_code }
        elsif scenario_def["scenario_card_name"]
          puts "  ! Could not find scenario card '#{scenario_card_name}' with an encounter_code in pack '#{pack_code}', skipping"
          next
        end
      end

      # "Hidden" cards are the reverse side of a front card, printed as a
      # separate ArkhamDB entry linked via back_link (in either direction -
      # sometimes the front points forward to the hidden back, sometimes the
      # hidden back points backward to the front). Their faction_code can
      # differ from the front (e.g. a neutral asset hidden behind a mythos
      # story card), so this scan runs over ALL cards in the pack, not just
      # the mythos-tagged ones, or hidden backs with a different faction get
      # missed and their front is wrongly marked as single-sided.
      hidden_codes = cards.select { |c| c["hidden"] }.map { |c| c["code"] }.to_set
      backward_targets = cards.select { |c| c["hidden"] && c["back_link"] }.map { |c| c["back_link"] }.to_set

      # Encounter-side cards are marked faction_code "mythos". Player cards
      # released alongside a scenario (faction guardian/seeker/etc) are not
      # part of the scenario's printed encounter set, so we skip them here -
      # but only after the hidden-card scan above, since a hidden back can
      # itself be a non-mythos player-faction card.
      encounter_cards = cards.select { |c| c["faction_code"] == "mythos" }
      front_cards = encounter_cards.reject { |c| c["hidden"] }

      scenario_cards = front_cards.map do |card|
        has_back = card["double_sided"] == true ||
          card.key?("back_text") ||
          hidden_codes.include?(card["back_link"]) ||
          backward_targets.include?(card["code"])
        {
          "id" => card["code"],
          "has_back" => has_back,
          "quantity" => card["quantity"] || 1
        }
      end

      missions[title] = { "scenario_cards" => scenario_cards }
      puts "  -> #{scenario_cards.size} cards"
    end

    campaign_data = {
      "name" => campaign_name,
      "missions_count" => missions.size,
      "missions" => missions
    }

    output_path = Rails.root.join(output_file)
    File.write(output_path, JSON.pretty_generate(campaign_data))
    puts "Wrote #{output_path}"

    # Register (or update) this campaign in scenarios.json
    index_path = Rails.root.join("scenarios.json")
    index = JSON.parse(File.read(index_path))
    index["campaigns"] ||= []
    index["campaigns"].reject! { |c| c["file"] == output_file }
    index["campaigns"] << {
      "name" => campaign_name,
      "file" => output_file,
      "scenarios" => scenario_defs.map { |s| { "title" => s["title"], "label" => s["label"] } }
    }
    File.write(index_path, JSON.pretty_generate(index))
    puts "Updated #{index_path}"
  end
end
