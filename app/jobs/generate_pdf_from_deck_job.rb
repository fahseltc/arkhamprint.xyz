class GeneratePdfFromDeckJob < GeneratePdfBaseJob
  DUPLEX_MODES = %w[none long_edge short_edge].freeze

  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      @deck_id = pdf_params["deck_id"]
      raise ArgumentError, "deck_id must be present" unless @deck_id.present?
      @print_backs  = pdf_params["print_backs"] != false
      @duplex_mode  = DUPLEX_MODES.include?(pdf_params["duplex_mode"]) ? pdf_params["duplex_mode"] : "none"
      @gap          = pdf_params["card_spacing"] == false ? PdfHelper::NO_GAP : PdfHelper::DEFAULT_GAP
      pdf_bin = generate_pdf_bin
      s3_key = upload_to_s3(pdf_bin)
    rescue PdfGenerationCancelled
      @pdf_job.update!(status: "cancelled")
    rescue => e
      @pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end

  def generate_pdf_bin
    # cards_hash is { front_image_url => quantity }
    cards_hash = get_cards_hash
    images_per_card = @print_backs ? 2 : 1
    total_images = cards_hash.values.sum * images_per_card
    Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{cards_hash.values.sum} duplex=#{@print_backs} duplex_mode=#{@duplex_mode}")

    if @print_backs
      records = build_records_with_backs(cards_hash, total_images)
      PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode, gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    else
      @pdf_job.update!(max_progress: total_images, current_progress: 0)
      PdfHelper.generate(cards_hash, "LETTER", gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    end
  end

  def get_cards_hash
    cards = ArkhamDbHelper.get_cards_from_deck_id(@deck_id)
                          .transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
    Rails.logger.info(cards)
    cards
  end
end