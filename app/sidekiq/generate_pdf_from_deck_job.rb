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

      # Option A: Save to local disk
      # file_path = Rails.root.join("tmp/pdf/pdf_job_#{pdf_job.id}.pdf")
      # File.open(file_path, "wb") { |f| f.write(pdf_binary) }
      # pdf_job.update!(status: 'completed', file_url: file_path.to_s)
      file = CarrierWave::SanitizedFile.new(
        tempfile: Tempfile.new([ "deck", ".pdf" ]).tap do |f|
          f.binmode
          f.write(pdf_binary)
          f.rewind
        end,
        filename: "deck_#{deck_id}_#{self.jid}.pdf"
      )

      uploader = PdfUploader.new
      uploader.store!(file)

      pdf_job.update!(
        status: "completed",
        file_url: uploader.file.path # S3 object key
      )
      Rails.logger.info("Job with ID:#{pdf_job.id} has finished successfully with file_url: #{pdf_job.file_url}")

    rescue => e
      pdf_job.update!(status: "failed", error_message: e.message)
      raise
    end
  end
end
