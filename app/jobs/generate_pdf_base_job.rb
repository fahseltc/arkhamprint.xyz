class GeneratePdfBaseJob < ApplicationJob
  BASE_BUCKET_PATH = "uploads/pdf/deck_"

  def generate_pdf_bin
    cards_hash = get_cards_hash
    @pdf_job.update!(max_progress: cards_hash.values.sum)
    pdf_binary = PdfHelper.generate(cards_hash, "LETTER") do |idx|
      @pdf_job.update!(current_progress: idx)
    end
    pdf_binary
  end

  def upload_to_s3(pdf_binary)
    s3_key = "#{BASE_BUCKET_PATH}#{@pdf_job.id}.pdf"
    s3_client = Aws::S3::Resource.new(region: ENV.fetch("AWS_REGION"))
    bucket = s3_client.bucket(ENV.fetch("AWS_BUCKET"))
    object = bucket.object(s3_key)

    object.put(
      body: pdf_binary,
      content_type: "application/pdf",
      acl: "private"
    )
    Rails.logger.info("uploaded #{s3_key} to s3")
    @pdf_job.update!(
      status: "completed",
      file_url: s3_key,
      current_progress: @pdf_job.max_progress
    )
    s3_key
  end



  # begin
  #   cards = ArkhamDbHelper.get_cards_from_deck_id(deck_id, include_investigator).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
  #   Rails.logger.info(cards)
  #   pdf_job.update!(current_progress: 0, max_progress: cards.values.sum)

  #   pdf_binary = PdfHelper.generate(cards, "LETTER") do |idx|
  #     pdf_job.update!(current_progress: idx)
  #   end

  #   s3_key = "uploads/pdfs/deck_#{deck_id}_#{pdf_job.id}.pdf"
  #   s3_client = Aws::S3::Resource.new(region: ENV.fetch("AWS_REGION"))
  #   bucket = s3_client.bucket(ENV.fetch("AWS_BUCKET"))
  #   object = bucket.object(s3_key)

  #   object.put(
  #     body: pdf_binary,
  #     content_type: "application/pdf",
  #     acl: "private"
  #   )

  #   pdf_job.update!(
  #     status: "completed",
  #     file_url: s3_key,
  #     current_progress: pdf_job.max_progress
  #   )
  #   Rails.logger.info("Job #{pdf_job.id} completed successfully: #{pdf_job.file_url}")

  # rescue => e
  #   pdf_job.update!(status: "failed", error_message: e.message)
  #   raise
  # end
  # end

  # Cards hash is in the form of https://URLs => card_count
  # {
  #     https://arkhamdb.com/bundles/cards/01025.png"=>2,
  #     https://arkhamdb.com/bundles/cards/04265.png"=>1
  # }
  #
  def get_cards_hash
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end
end
