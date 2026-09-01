class GeneratePdfFromScenarioJob < GeneratePdfBaseJob
  DUPLEX_MODES = %w[none long_edge short_edge].freeze

  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      scenario_title = pdf_params.fetch("scenario_title")
      campaign_file = pdf_params.fetch("campaign_file")
      @duplex_mode = DUPLEX_MODES.include?(pdf_params["duplex_mode"]) ? pdf_params["duplex_mode"] : "none"
      @print_backs = param_flag(pdf_params["print_backs"])
      @gap = resolve_gap(pdf_params["card_spacing"])

      index_path = Rails.root.join("scenarios.json")
      index = JSON.parse(File.read(index_path))
      campaign = index.fetch("campaigns", []).find { |entry| entry["file"] == campaign_file }
      raise "Campaign not found" unless campaign

      scenario_file = File.read(Rails.root.join(campaign_file))
      scenario_json = JSON.parse(scenario_file)
      missions = scenario_json.fetch("missions", {})

      scenario = missions[scenario_title]
      raise "Scenario not found" if scenario.nil?
      @scenario_cards = scenario["scenario_cards"]

      raise "Scenario has no cards" if @scenario_cards.empty?

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
    records = get_scenario_card_records
    images_per_card = @print_backs ? 2 : 1
    @pdf_job.update!(max_progress: records.sum { |r| r[:quantity] } * images_per_card)
    Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{records.sum { |r| r[:quantity] }} duplex=#{@print_backs} duplex_mode=#{@duplex_mode}")

    if @print_backs
      PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode, gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    else
      front_counts = Hash.new(0)
      records.each { |r| front_counts[r[:front_url]] += r[:quantity] }
      PdfHelper.generate(front_counts, "LETTER", gap: @gap, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    end
  end

  def get_scenario_card_records
    @scenario_cards.map do |card_info|
      # normalizing the id for use with the back side
      original_id = card_info["id"]
      base_id = original_id.end_with?("a") ? original_id.delete_suffix("a") : original_id

      front_url = ArkhamDbHelper.get_card_image_url(original_id)
      back_url = if card_info["has_back"]
        ArkhamDbHelper.get_card_image_url("#{base_id}b")
      else
        CardBackHelper.path_for(card_info["faction_code"])
      end

      { front_url: front_url, back_url: back_url, quantity: card_info["quantity"] }
    end
  end
end
