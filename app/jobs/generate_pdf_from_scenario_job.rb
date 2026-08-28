class GeneratePdfFromScenarioJob < GeneratePdfBaseJob
  DUPLEX_MODES = %w[none long_edge short_edge].freeze

  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      scenario_title = pdf_params.fetch("scenario_title")
      campaign_file = pdf_params.fetch("campaign_file")
      @duplex_mode = DUPLEX_MODES.include?(pdf_params["duplex_mode"]) ? pdf_params["duplex_mode"] : "none"

      index_path = Rails.root.join("scenarios.json")
      index = JSON.parse(File.read(index_path))
      campaign = index.fetch("campaigns", []).find { |entry| entry["file"] == campaign_file }
      raise "Campaign not found" unless campaign

      scenario_file = File.read(Rails.root.join(campaign_file))
      scenario_json = JSON.parse(scenario_file)

      @scenario = scenario_json.fetch("missions", {})[scenario_title]

      if @scenario.nil?
        raise "Scenario not found"
      end

      if @scenario["scenario_cards"].empty?
        raise "Scenario has no cards"
      end

      pdf_bin = generate_pdf_bin
      s3_key = upload_to_s3(pdf_bin)
    rescue => e
      @pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end
  def generate_pdf_bin
    records = get_scenario_card_records
    @pdf_job.update!(max_progress: records.sum { |r| r[:quantity] } * 2)
    PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode) do |idx|
      @pdf_job.update!(current_progress: idx)
    end
  end

  def get_scenario_card_records
    @scenario["scenario_cards"].map do |card_info|
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
