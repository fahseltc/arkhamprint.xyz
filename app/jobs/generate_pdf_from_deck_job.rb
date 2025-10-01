class GeneratePdfFromDeckJob < GeneratePdfBaseJob
  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      @deck_id = pdf_params["deck_id"]
      raise ArgumentError, "deck_id must be present" unless @deck_id.present?
      @include_investigator = pdf_params["include_investigator"]
      pdf_bin = generate_pdf_bin
      s3_key = upload_to_s3(pdf_bin)
    rescue => e
      @pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end
  def get_cards_hash
    cards = ArkhamDbHelper.get_cards_from_deck_id(@deck_id, @include_investigator).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
    Rails.logger.info(cards)
    cards
  end
end
