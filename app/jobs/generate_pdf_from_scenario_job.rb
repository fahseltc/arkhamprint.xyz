class GeneratePdfFromScenarioJob < GeneratePdfBaseJob
  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      scenario_title = pdf_params.fetch("scenario_title")
      campaign_file = pdf_params.fetch("campaign_file")

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
  def get_cards_hash
    # {"https://arkhamdb.com/bundles/cards/10019.png"=>1}
    cards_data = @scenario["scenario_cards"]
    card_img_urls = {}
    cards_data.each do |card_info|
      quantity = card_info["quantity"]
      # normalizing the id for use with the back side
      original_id = card_info["id"]

      if original_id.end_with?("a")
        base_id = original_id.delete_suffix("a")
      else
        base_id = original_id
      end

      card_url = ArkhamDbHelper.get_card_image_url(original_id)
      card_img_urls[card_url] = quantity

      if card_info["has_back"]
        back_url = ArkhamDbHelper.get_card_image_url("#{base_id}b")
        card_img_urls[back_url] = quantity
      end
    end
    card_img_urls
  end
end
