class GeneratePdfFromScenarioJob < GeneratePdfBaseJob
  def perform(pdf_job_id, pdf_params)
    @pdf_job_id = pdf_job_id
    @pdf_job = PdfJob.find(@pdf_job_id)
    begin
      # load the json file from disk
      scenario_file = File.read(Rails.root.join("01_the_forgotten_age.json"))
      scenario_json = JSON.parse(scenario_file)
      scenario_title = pdf_params["scenario_title"]

      @scenario = scenario_json["missions"][scenario_title]

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
      card_url = ArkhamDbHelper.get_card_image_url(card_info["id"])
      card_img_urls[card_url] = quantity

      if card_info["has_back"]
        back_url = ArkhamDbHelper.get_card_image_url("#{card_info["id"]}b")
        card_img_urls[back_url] = quantity
      end
    end
    card_img_urls
  end
end
