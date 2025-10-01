class GeneratePdfFromCardListJob < GeneratePdfBaseJob
  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      @card_ids = Array(pdf_params["card_ids"]).map(&:to_s) if pdf_params["card_ids"].present?
      raise ArgumentError, "card_ids must be present" unless @card_ids.present?
      pdf_bin = generate_pdf_bin
      s3_key = upload_to_s3(pdf_bin)
    rescue => e
      @pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end

  def get_cards_hash
    cards_hash = {}
    @card_ids.each do |id|
      img_url = ArkhamDbHelper.get_card_image_url(id)
      if img_url.present?
        if cards_hash[img_url].nil?
          cards_hash[img_url] = 1
        else
          cards_hash[img_url] += 1
        end
      end
    end
    Rails.logger.info(cards_hash)
    cards_hash
  end
end
