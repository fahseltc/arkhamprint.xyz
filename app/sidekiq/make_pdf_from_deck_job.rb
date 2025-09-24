class MakePdfFromDeckJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(deck_id)
    card_urls = ArkhamDbHelper.get_cards_from_deck_id(id).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) } # could do multiple API calls at once?
    data = PdfHelper.generate(card_urls, "LETTER")
    # card = get_card(card_id)
    # pp "https://arkhamdb.com" + card["imagesrc"]
  end



  # def get_card(card_id)
  #   card_api = "https://arkhamdb.com/api/public/card/"
  #   pp card_api + card_id.to_s
  #   response = HTTParty.get(card_api + card_id.to_s)
  #   if response.code == 200
  #     response
  #   else
  #     Rails.logger.error("error when trying to collect card with ID #{card_id}")
  #     nil
  #   end
  # end
end
