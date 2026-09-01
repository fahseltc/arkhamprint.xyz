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

    if @print_backs
      total_images = cards_hash.values.sum * 2
      Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{cards_hash.values.sum} duplex=true duplex_mode=#{@duplex_mode}")
      records = build_records_with_backs(cards_hash, total_images)
      PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode, gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    else
      # Front-only print. The investigator card is double-sided and its reverse
      # is real card content (stats/setup), not a decorative back — so include
      # it as its own front-facing card even though backs are off.
      cards_hash = add_investigator_back_as_front(cards_hash)
      total_images = cards_hash.values.sum
      Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{total_images} duplex=false")
      @pdf_job.update!(max_progress: total_images, current_progress: 0)
      PdfHelper.generate(cards_hash, "LETTER", gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    end
  end

  def get_cards_hash
    deck = ArkhamDbHelper.fetch_deck(@deck_id)
    @investigator_code = deck[:investigator_code]
    cards = deck[:cards].transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
    Rails.logger.info(cards)
    cards
  end

  # Adds the investigator's back-side image as a standalone front card, so the
  # reverse of the investigator sheet still prints when card backs are off.
  # No-op if there's no investigator or it has no distinct back.
  def add_investigator_back_as_front(cards_hash)
    return cards_hash unless @investigator_code

    meta = ArkhamDbHelper.get_card_back_info(@investigator_code)
    return cards_hash unless meta[:double_sided] && meta[:back_image_url]

    back_url = meta[:back_image_url]
    cards_hash[back_url] = (cards_hash[back_url] || 0) + 1
    Rails.logger.info("Added investigator back as front card: #{back_url}")
    cards_hash
  end
end