module ArkhamDbHelper
  def self.get_cards_from_deck_id(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    HTTParty.get(decklist_api + deck_id.to_s)["slots"].compact.reject { |id, quantity| id == "01000" }
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
