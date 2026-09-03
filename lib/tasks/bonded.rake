require "json"
require "net/http"
require "uri"

namespace :bonded do
  desc "Regenerate config/bonded_cards.json from the full ArkhamDB card list"
  task refresh: :environment do
    uri = URI("https://arkhamdb.com/api/public/cards/")
    puts "Fetching full card list from #{uri}..."
    cards = JSON.parse(Net::HTTP.get(uri))

    # Bonded cards reference their parent by NAME; decks reference cards by CODE.
    # Build name -> [codes] so we can key the output index by parent CODE.
    name_to_codes = Hash.new { |h, k| h[k] = [] }
    cards.each { |c| name_to_codes[c["name"]] << c["code"] if c["name"] && c["code"] }

    index = {}
    cards.each do |card|
      parent_name = card["bonded_to"]
      next unless parent_name && card["code"]

      entry = {
        "code"     => card["code"],
        "quantity" => (card["bonded_count"] || 1).to_i,
        "name"     => card["name"]
      }
      name_to_codes[parent_name].each do |parent_code|
        (index[parent_code] ||= []) << entry
      end
    end

    path = Rails.root.join("config", "bonded_cards.json")
    File.write(path, JSON.pretty_generate(index))
    puts "Wrote #{path} (#{index.size} parent codes, " \
         "#{index.values.map(&:size).sum} bonded entries)."
  end
end
