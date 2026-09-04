class CleanupLocalJsonJobFiles < ApplicationJob
  queue_as :default

  # How long a completed job's record (and any local PDF) is kept.
  COMPLETED_TTL = 24.hours

  # Grace period before a "pending" job with no progress is considered
  # abandoned. A freshly-created job sits in the :async queue as pending with
  # max_progress == 0 until it starts; on a busy/idle free-tier instance that
  # can take a while. Deleting it immediately (the old behaviour) could remove
  # a job that's still legitimately queued, out from under the running job.
  PENDING_GRACE = 1.hour

  def perform
    Rails.logger.info "Cleaning up local JSON job files"
    cleanup_job_files
    cleanup_local_pdfs
  end

  private

  def cleanup_job_files
    Dir.glob(Rails.root.join("tmp", "jobdata", "*.json")).each do |file_path|
      begin
        data   = JSON.parse(File.read(file_path))
        status = data["status"]
        mtime  = File.mtime(file_path)
        age    = Time.current - mtime

        should_delete = case status
        when "pending"           then data["max_progress"].to_i == 0 && age > PENDING_GRACE
        when "failed", "cancelled" then true
        when "completed"         then age > COMPLETED_TTL
        else false
        end

        next unless should_delete

        delete_job_file(file_path, data)
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Failed to process #{file_path}: #{e.message}"
      end
    end
  end

  # Local PDF storage (dev / FORCE_USE_LOCAL) has no S3 lifecycle rule to expire
  # old output, so prune it here: delete generated PDFs older than COMPLETED_TTL.
  def cleanup_local_pdfs
    dir = PdfStorage::LOCAL_DIR
    return unless Dir.exist?(dir)

    pruned = 0
    Dir.glob(dir.join("*.pdf")).each do |file_path|
      next unless Time.current - File.mtime(file_path) > COMPLETED_TTL

      File.delete(file_path)
      pruned += 1
    rescue StandardError => e
      Rails.logger.error "Failed to delete local PDF #{file_path}: #{e.message}"
    end
    Rails.logger.info "Cleaned up #{pruned} local PDF file(s)" if pruned.positive?
  end

  def delete_job_file(file_path, data)
    File.delete(file_path) if File.exist?(file_path)
    Rails.logger.info "Deleted PdfJob file: #{file_path} (status=#{data["status"]})"
  rescue StandardError => e
    Rails.logger.error "Failed to delete #{file_path}: #{e.message}"
  end
end
