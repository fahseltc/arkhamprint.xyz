require "uri"

class GeneratePdfFromDeckJob < GeneratePdfBaseJob
  DUPLEX_MODES = %w[none long_edge short_edge].freeze

  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      @deck_id = pdf_params["deck_id"]
      raise ArgumentError, "deck_id must be present" unless @deck_id.present?
      @include_investigator = pdf_params["include_investigator"]
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
    cards_hash = get_cards_hash
    images_per_card = @print_backs ? 2 : 1
    @pdf_job.update!(max_progress: cards_hash.values.sum * images_per_card)

    if @print_backs
      records = cards_hash.map do |url, quantity|
        base_id = File.basename(URI.parse(url).path, ".*")
        back_url = ArkhamDbHelper.get_card_image_url("#{base_id}b")
        { front_url: url, back_url: back_url, quantity: quantity }
      end
      PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode, gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    else
      PdfHelper.generate(cards_hash, "LETTER", gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    end
  end

  def get_cards_hash
    cards = ArkhamDbHelper.get_cards_from_deck_id(@deck_id, @include_investigator).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
    Rails.logger.info(cards)
    cards
  end
end