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
# A "Non-Scenario Encounters" entry (any pack_code, that exact title) collects
# whatever mythos cards in its pack weren't claimed by any other scenario in
# the config - the shared/side encounter sets not tied to one numbered
# scenario. It's always resolved last regardless of where it appears in the
# scenarios array.
#
# A handful of scenarios span more than one encounter_code for distinct named
# parts (e.g. Ice and Death in Edge of the Earth has three), which can't be
# reached by looking up a single scenario card. For those, set
# `encounter_codes` to an explicit array instead of relying on
# `scenario_card_name` lookup.
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
#     { "pack_code": "wos", "title": "The Wages of Sin", "label": "2. The Wages of Sin" },
#     { "pack_code": "eoec", "title": "Ice and Death", "label": "1. Ice and Death",
#       "encounter_codes": [ "ice_and_death", "the_crash", "lost_in_the_night", "seeping_nightmares" ] }
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
    pack_cache = {}
    claimed_encounter_codes = Hash.new { |h, k| h[k] = Set.new }

    # ArkhamDB occasionally answers with HTTP 200 and an empty/truncated body
    # under load. Retry a few times before giving up on a pack, and cache each
    # pack's cards since several scenarios in a config can share a pack_code.
    fetch_pack = lambda do |pack_code|
      pack_cache.fetch(pack_code) do
        cards = nil
        3.times do |attempt|
          response = HTTParty.get("https://arkhamdb.com/api/public/cards/#{pack_code}")
          if response.code == 200 && response.body.present?
            begin
              cards = JSON.parse(response.body)
              break
            rescue JSON::ParserError
              # fall through to retry
            end
          end
          puts "  ! Attempt #{attempt + 1} failed fetching pack '#{pack_code}' (HTTP #{response.code}), retrying..."
          sleep(1)
        end
        pack_cache[pack_code] = cards
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
    build_scenario_cards = lambda do |cards|
      hidden_codes = cards.select { |c| c["hidden"] }.map { |c| c["code"] }.to_set
      backward_targets = cards.select { |c| c["hidden"] && c["back_link"] }.map { |c| c["back_link"] }.to_set

      # Encounter-side cards are marked faction_code "mythos". Player cards
      # released alongside a scenario (faction guardian/seeker/etc) are not
      # part of the scenario's printed encounter set, so we skip them here -
      # but only after the hidden-card scan above, since a hidden back can
      # itself be a non-mythos player-faction card.
      front_cards = cards.select { |c| c["faction_code"] == "mythos" }.reject { |c| c["hidden"] }

      front_cards.map do |card|
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
    end

    # "Non-Scenario Encounters" entries are processed after every other
    # scenario in the config, regardless of where they appear in the JSON, so
    # that we know which encounter_codes the pack's real scenarios already
    # claimed. What's left over in the pack is the shared/side encounter
    # content not tied to a specific numbered scenario. If nothing else in
    # the config claims cards from this pack (e.g. a campaign's mythos packs
    # are entirely separate from its deluxe box), nothing is excluded and the
    # whole pack's mythos cards are used.
    regular_defs, side_encounter_defs = scenario_defs.partition { |s| s.fetch("title") != "Non-Scenario Encounters" }

    (regular_defs + side_encounter_defs).each do |scenario_def|
      pack_code = scenario_def.fetch("pack_code")
      title = scenario_def.fetch("title")

      puts "Fetching pack '#{pack_code}' for scenario '#{title}'..."
      cards = fetch_pack.call(pack_code)

      if cards.nil?
        puts "  ! Failed to fetch pack '#{pack_code}' after retries, skipping"
        next
      end

      if title == "Non-Scenario Encounters"
        cards = cards.select { |c| c["faction_code"] == "mythos" && !claimed_encounter_codes[pack_code].include?(c["encounter_code"]) }
      else
        # Newer campaign-expansion packs contain several scenarios in one
        # pack. ArkhamDB associates cards with an encounter_code, and the
        # scenario card itself provides the code we need to isolate one
        # scenario. We only filter down to a single encounter_code when the
        # pack actually holds more than one distinct scenario - some
        # single-scenario packs (e.g. Heart of the Elders) legitimately span
        # several encounter_codes for their branching sub-locations, and
        # filtering to just the scenario card's own code would drop those
        # cards. Some scenarios (e.g. Ice and Death in Edge of the Earth)
        # span several encounter_codes for distinct numbered parts that
        # aren't reachable from a single scenario card at all - for those,
        # set `encounter_codes` explicitly in the config instead of relying
        # on lookup by name.
        scenario_card_name = scenario_def["scenario_card_name"] || title
        distinct_scenarios_in_pack = cards.select { |c| c["type_code"] == "scenario" }.map { |c| c["name"] }.uniq
        if scenario_def["encounter_codes"]
          cards = cards.select { |c| scenario_def["encounter_codes"].include?(c["encounter_code"]) }
        elsif scenario_def["scenario_card_name"] || distinct_scenarios_in_pack.size > 1
          scenario_card = cards.find { |c| c["name"] == scenario_card_name && c["type_code"] == "scenario" }
          if scenario_card && scenario_card["encounter_code"]
            encounter_code = scenario_card["encounter_code"]
            cards = cards.select { |c| c["encounter_code"] == encounter_code }
          else
            puts "  ! Could not find scenario card '#{scenario_card_name}' with an encounter_code in pack '#{pack_code}', skipping"
            next
          end
        end

        cards.each { |c| claimed_encounter_codes[pack_code] << c["encounter_code"] if c["faction_code"] == "mythos" }
      end

      scenario_cards = build_scenario_cards.call(cards)
      missions[title] = { "scenario_cards" => scenario_cards }
      puts "  -> #{scenario_cards.size} cards"
    end

    # Re-order missions to match the config's original scenario order (the
    # loop above processes "Non-Scenario Encounters" last regardless of
    # position so its claimed-code exclusion works correctly).
    missions = scenario_defs.filter_map { |s| [ s.fetch("title"), missions[s.fetch("title")] ] if missions.key?(s.fetch("title")) }.to_h

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
