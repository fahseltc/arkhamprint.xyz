module ArkhamDbHelper
  def self.get_cards_from_deck_id(deck_id, include_investigator = false)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    response = HTTParty.get(decklist_api + deck_id.to_s)

    # Extract only what's needed before dropping the response object
    slots = response["slots"].compact.reject { |id, _quantity| id == "01000" }
    investigator_code = include_investigator ? response["investigator_code"] : nil
    response = nil # allow GC to reclaim the full parsed response body

    cards = if investigator_code
      { investigator_code => 1, "#{investigator_code}b" => 1 }.merge(slots)
    else
      slots
    end

    Rails.logger.info(cards)
    cards
  end

  def self.get_card(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    response = HTTParty.get(card_api + card_id.to_s)
    if response.code == 200
      response
    else
      Rails.logger.error("error when trying to collect card with ID #{card_id}")
      nil
    end
  end

  def self.get_card_image_url(card_id)
    "https://arkhamdb.com/bundles/cards/" + card_id  + ".png"
  end

  def self.get_all_cards
    HTTParty.get("https://arkhamdb.com/api/public/cards/")
  end
end
