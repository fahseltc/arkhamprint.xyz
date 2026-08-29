require "aws-sdk-s3"

class GeneratePdfBaseJob < ApplicationJob
  BASE_BUCKET_PATH = "uploads/pdf/deck_"

  def generate_pdf_bin
    cards_hash = get_cards_hash
    @pdf_job.update!(max_progress: cards_hash.values.sum)
    pdf_tmp = PdfHelper.generate(cards_hash, "LETTER", job_id: @pdf_job.id) do |idx|
      report_progress(idx)
    end
    pdf_tmp
  end

  # Cooperative cancellation: the "Cancel" button (see pdf_jobs_controller's
  # cancel action) just flips the job's stored status, so the running job has
  # to notice it itself - checked on every drawn image, same cadence as the
  # progress update it rides along with. Checked BEFORE updating progress:
  # `@pdf_job` is a stale in-memory snapshot (its `status` is whatever it was
  # when the job started), and `update!`/`save!` writes the whole record, so
  # updating first would overwrite a fresh "cancelled" back to "pending".
  def report_progress(idx)
    raise PdfGenerationCancelled if PdfJob.find(@pdf_job.id).status == "cancelled"
    @pdf_job.update!(current_progress: idx)
  end

  def upload_to_s3(pdf_tmp)
    s3_key = "#{BASE_BUCKET_PATH}#{@pdf_job.id}.pdf"
    s3_client = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION"))

    File.open(pdf_tmp.path, "rb") do |file|
      s3_client.put_object(
        bucket: ENV.fetch("AWS_BUCKET"),
        key: s3_key,
        body: file,
        content_type: "application/pdf",
        acl: "private"
      )
    end

    Rails.logger.info("uploaded #{s3_key} to s3")
    @pdf_job.update!(
      status: "completed",
      file_url: s3_key,
      current_progress: @pdf_job.max_progress
    )
    s3_key
  ensure
    pdf_tmp.close!
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
