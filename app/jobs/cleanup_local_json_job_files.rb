class CleanupLocalJsonJobFiles < ApplicationJob
  queue_as :default

  TMP_DIR = Rails.root.join("tmp", "jobdata")
  S3_BUCKET = ENV.fetch("AWS_BUCKET")
  S3_REGION = ENV.fetch("AWS_REGION")

  def perform
    s3 = Aws::S3::Resource.new(region: S3_REGION)
    bucket = s3.bucket(S3_BUCKET)

    Dir.glob(TMP_DIR.join("*.json")).each do |file_path|
      begin
        data = JSON.parse(File.read(file_path))
        status = data["status"]
        max_progress = data["max_progress"].to_i
        file_url = data["file_url"]
        job_id = data["job_jid"] || File.basename(file_path, ".json") # fallback if no job_id
        deck_id = extract_deck_id(file_url) # implement this below

        # Check if the job should be deleted
        if (status == "pending" && max_progress == 0) || status == "failed"
          # Delete S3 PDF using s3_key pattern
          if deck_id && job_id
            s3_key = "uploads/pdfs/deck_#{deck_id}_#{job_id}.pdf"
            object = bucket.object(s3_key)
            object.delete if object.exists?
            Rails.logger.info "Deleted S3 PDF: #{s3_key}"
          end

          # Delete the JSON file
          File.delete(file_path)
          Rails.logger.info "Deleted PdfJob JSON: #{file_path}"
        end

      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Failed to delete #{file_path}: #{e.message}"
      end
    end
  end

  private

  # Extract deck_id from local file_url or S3 path
  # Example file_url: "uploads/pdfs/deck_1234_5678.pdf"
  def extract_deck_id(file_url)
    return nil unless file_url.present?
    match = file_url.match(/deck_(\d+)_\w+\.pdf/)
    match[1] if match
  end
end
