class CardController < ActionController::Base # this sends the file correctly, using ApplicationController gives assets but also prevents the file from sending.
  def from_deck
    /(?<id>\d+)/ =~ params[:id]
    page_size = params[:page_size]
    Rails.logger.info(id)
    Rails.logger.info(page_size) # this is an INT instead of a string right now - need ENUM lookup probably
    # card_urls = ArkhamDbHelper.get_cards_from_deck_id(id).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) } # could do multiple API calls at once?
    # Rails.logger.info(card_urls)
    card_urls = Hash.new()
    card_urls["https://arkhamdb.com/bundles/cards/60115.png"] = 3
    data = PdfHelper.generate(card_urls, "LETTER")
    send_data data, type: "application/pdf", filename: "test.pdf", disposition: "attachment"
  end

  def from_card_list
    # Example input string
    # 01022,    01044
    Rails.logger.info(params[:card_ids])
    if params[:card_ids].nil?
      return false
    end
    card_ids = params[:card_ids].gsub!(/[[:space:]]/, "").split(",")
    if card_ids.length > 40
      Rails.logger.error("raise error, input too long")
    end
    card_hash = {}
    card_ids.each do |id|
      img_url = ArkhamDbHelper.get_card_image_url(id)
      card_hash[img_url] = 1
    end
    Rails.logger.info(card_hash)
    data = PdfHelper.generate(card_hash, "LETTER")
    response.content_type = "application/pdf"
    send_data(data, :filename => "test.pdf", :type => "application/pdf", :disposition => "attachment") # attachment // inline
    #render :nothing => true
  end
end
