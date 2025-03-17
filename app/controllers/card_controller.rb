class CardController < ActionController::Base
    def home
    end

    def new
        /(?<id>\d+)/ =~ params[:id]
        page_size = params[:page_size]
        Rails.logger.info(id)
        Rails.logger.info(page_size) # this is an INT instead of a string right now - need ENUM lookup probably
        card_urls = ArkhamDbHelper.get_cards_from_deck_id(id).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) } # could do multiple API calls at once?
        Rails.logger.info(card_urls)
        #card_urls = Hash.new()
        #card_urls["https://arkhamdb.com/bundles/cards/60115.png"] = 3
        send_data PdfHelper.generate(card_urls, "LETTER"), filename: "cards.pdf"
    end
end