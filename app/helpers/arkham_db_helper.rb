module ArkhamDbHelper

    def self.get_cards_from_deck_id(deck_id)
        decklist_api = "https://arkhamdb.com/api/public/decklist/"
        HTTParty.get(decklist_api + deck_id.to_s)["slots"].compact.reject {|id, quantity| id == "01000"}
    end

    def self.get_card(card_id)
        card_api = "https://arkhamdb.com/api/public/card/"
        HTTParty.get(card_api + card_id.to_s)
    end

    def self.get_card_image_url(card_id)
        "https://arkhamdb.com" + self.get_card(card_id)["imagesrc"]
    end

    def self.get_all_cards
        HTTParty.get("https://arkhamdb.com/api/public/cards/")
    end

    
    #   def card_ids(deck_id)
    #     decklist_api = "https://arkhamdb.com/api/public/decklist/"
    #     HTTParty.get(decklist_api + deck_id)["slots"].compact.reject {|id, quantity| id == "01000"}
    #   end
    
    #   def card_image_url(card_id)
    #     card_api = "https://arkhamdb.com/api/public/card/"
    #     "https://arkhamdb.com" + HTTParty.get(card_api + card_id)["imagesrc"]
    #   end
end