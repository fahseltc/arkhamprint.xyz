class FromDeckIdJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(deck_id, uuid)
    Rails.logger.info("Starting job with ID:#{self.jid}, deck_id:#{deck_id}, uuid:#{uuid}")
    card_urls = ArkhamDbHelper.get_cards_from_deck_id(deck_id).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) } # could do multiple API calls at once?
    save_path = Rails.root.join("tmp", "pdf", uuid.to_s + ".pdf")
    PdfHelper.new.generate(card_urls, "LETTER", save_path, self.jid)
    Rails.logger.info("Finished job with ID:#{self.jid}, deck_id:#{deck_id}, uuid:#{uuid}")
  end
end
