class FromCardListJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(card_ids, uuid)
    Rails.logger.info("Starting job with ID:#{self.jid}, card_ids:#{card_ids}, uuid:#{uuid}")
    save_path = Rails.root.join("tmp", "pdf", uuid.to_s + ".pdf")
    card_hash = {}
    card_ids.each do |id|
      img_url = ArkhamDbHelper.get_card_image_url(id)
      if img_url.present?
        if card_hash[img_url].nil? # handle duplicate input ID's
          card_hash[img_url] = 1
        else
          card_hash[img_url] += 1
        end
      end
    end
    PdfHelper.new.generate(card_hash, "LETTER", save_path, self.jid)
    Rails.logger.info("Finished job with ID:#{self.jid}, card_ids:#{card_ids}, uuid:#{uuid}")
  end
end
