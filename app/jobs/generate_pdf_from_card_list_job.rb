class GeneratePdfFromCardListJob < GeneratePdfBaseJob
  DUPLEX_MODES = %w[none long_edge short_edge].freeze

  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      @card_ids    = Array(pdf_params["card_ids"]).map(&:to_s) if pdf_params["card_ids"].present?
      raise ArgumentError, "card_ids must be present" unless @card_ids.present?
      @print_backs = param_flag(pdf_params["print_backs"])
      @duplex_mode = DUPLEX_MODES.include?(pdf_params["duplex_mode"]) ? pdf_params["duplex_mode"] : "none"
      @gap         = param_flag(pdf_params["card_spacing"]) ? PdfHelper::DEFAULT_GAP : PdfHelper::NO_GAP
      pdf_bin = generate_pdf_bin
      store_pdf(pdf_bin)
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
    cards_hash = {}
    @card_ids.each do |id|
      img_url = ArkhamDbHelper.get_card_image_url(id)
      cards_hash[img_url] = (cards_hash[img_url] || 0) + 1 if img_url.present?
    end
    Rails.logger.info(cards_hash)
    cards_hash
  end
end
