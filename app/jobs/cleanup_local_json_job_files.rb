class CleanupLocalJsonJobFiles < ApplicationJob
  queue_as :default

  # Jobs are eligible for deletion when they meet any of these conditions:
  #   - status "pending" with no progress (job was never picked up)
  #   - status "failed" or "cancelled"
  #   - status "completed" and the file is older than COMPLETED_TTL
  COMPLETED_TTL = 24.hours

  def perform
    Rails.logger.info "Cleaning up local JSON job files"

    Dir.glob(Rails.root.join("tmp", "jobdata", "*.json")).each do |file_path|
      begin
        data   = JSON.parse(File.read(file_path))
        status = data["status"]
        mtime  = File.mtime(file_path)

        should_delete = case status
        when "pending"   then data["max_progress"].to_i == 0
        when "failed",
             "cancelled" then true
        when "completed" then Time.current - mtime > COMPLETED_TTL
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

  private

  def delete_job_file(file_path, data)
    File.delete(file_path) if File.exist?(file_path)
    Rails.logger.info "Deleted PdfJob file: #{file_path} (status=#{data["status"]})"
  rescue StandardError => e
    Rails.logger.error "Failed to delete #{file_path}: #{e.message}"
  end
end
