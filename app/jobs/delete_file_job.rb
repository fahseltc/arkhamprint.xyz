class DeleteFileJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(file_path)
    begin
      FileUtils.remove_entry_secure(file_path)
    rescue StandardError => e
    end
  end
end