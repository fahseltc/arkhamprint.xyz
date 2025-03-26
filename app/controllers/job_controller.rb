class JobController < ActionController::Base
  def from_deck
    if params[:deck_url].nil?
      render json: { error: "Invalid deck_url" }, status: 404
      return
    end

    /(?<id>\d+)/ =~ params[:deck_url]
    # TODO validate URL
    file_id = ('a'..'z').to_a.shuffle[0,32].join
    job_id = FromDeckIdJob.perform_async(id, file_id)
    Rails.logger.info("job_id: #{job_id}")
    render json: { job_id: job_id, file_id: file_id }
  end

  def download
    file_id = params[:file_id]
    base_path = Rails.root.join("tmp", "pdf")
    valid = verify_download_path(base_path, file_id)
    if !valid
      render json: { error: "Invalid file_id" }, status: 404
      return
    end
    download_path = build_download_path(base_path, file_id)
    if File.file? download_path
      response.content_type = "application/pdf"
      DeleteFileJob.perform_in(3.minutes, download_path.to_s)
      send_file download_path, :filename => "#{file_id}.pdf", :type => "application/pdf", :disposition => "attachment"
    else
      render json: { error: "File not present" }, status: 404
    end
  end

  def verify_download_path(base_path, file_id)
    # User provided UUID to be used in a file path - verify things are OK
    download_path = build_download_path(base_path, file_id)
    if download_path.relative? # ensure file_id string is not a relative path
      return false
    elsif file_id.include?(".") # ensure file_id string doesnt have any periods
      return false
    elsif download_path.to_s.exclude?(base_path.to_s) # ensure the save_path results in something containing the base_path
      return false
    else
      return true
    end
  end

  def build_download_path(base_path, file_id)
    base_path.join(file_id.to_s + ".pdf")
  end
end
#   def status
#     job_id = params[:job_id]
#   end


#   end


# end

