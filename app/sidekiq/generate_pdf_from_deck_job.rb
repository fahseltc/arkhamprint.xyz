class GeneratePdfFromDeckJob
  include Sidekiq::Job
  sidekiq_options retry: false

  # sidekiq_options retry: 3

  def perform(pdf_job_id, deck_id)
    pdf_job = PdfJob.find(pdf_job_id)
    pdf_job.update!(status: "processing")

    begin
      # Generate PDF
      card_urls = ArkhamDbHelper.get_cards_from_deck_id(deck_id).transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) } # could do multiple API calls at once?
      pdf_binary = PdfHelper.generate(card_urls, "LETTER")

      s3_key = "uploads/pdfs/deck_#{deck_id}_#{jid}.pdf"
      s3_client = Aws::S3::Resource.new(region: ENV.fetch("AWS_REGION"))
      bucket = s3_client.bucket(ENV.fetch("AWS_BUCKET"))
      object = bucket.object(s3_key)

      object.put(
        body: pdf_binary,
        content_type: "application/pdf",
        acl: "private" # keep private, presign later
      )

      pdf_job.update!(
        status: "completed",
        file_url: s3_key # S3 object key
      )
      Rails.logger.info("Job with ID:#{pdf_job.id} has finished successfully with file_url: #{pdf_job.file_url}")

    rescue => e
      pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
