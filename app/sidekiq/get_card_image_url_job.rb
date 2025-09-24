class GetCardImageUrlJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(card_id)
    card = get_card(card_id)
    pp "https://arkhamdb.com" + card["imagesrc"]
  end

  def get_card(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    pp card_api + card_id.to_s
    response = HTTParty.get(card_api + card_id.to_s)
    if response.code == 200
      response
    else
      Rails.logger.error("error when trying to collect card with ID #{card_id}")
      nil
    end
  end
end
