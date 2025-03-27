require "sidekiq/api"

class JobController < ActionController::Base
  def from_deck
    if params[:deck_url].nil?
      render json: { error: "Invalid deck_url" }, status: 404
      return
    end

    /(?<id>\d+)/ =~ params[:deck_url]
    # TODO validate URL
    file_id = get_file_id()
    job_id = FromDeckIdJob.perform_async(id, file_id)
    if job_id.present?
      render json: { job_id: job_id, file_id: file_id }
    else
      render json: { error: "Error submitting job." }, status: 404
    end
  end

  def from_card_list
    if params[:card_ids].nil?
      render json: { error: "Invalid list of card IDs" }, status: 404
      return
    end
    file_id = get_file_id()
    card_ids = params[:card_ids].gsub(/[[:space:]]/, "").split(",")
    if card_ids.length > 40
      Rails.logger.error("raise error, input too long")
    end
    Rails.logger.error(card_ids)
    job_id = FromCardListJob.perform_async(card_ids, file_id)
    if job_id.present?
      render json: { job_id: job_id, file_id: file_id }
    else
      render json: { error: "Error submitting job." }, status: 404
    end
  end

  def get_file_id
    ("a".."z").to_a.shuffle[0, 32].join
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
      send_file download_path, filename: "#{file_id}.pdf", type: "application/pdf", disposition: "attachment"
    else
      render json: { error: "File not present" }, status: 404
    end
  end

  # These methods dont seem reliable
  # def status
  #   job_id = params[:job_id]
  #   was_queued = ActiveModel::Type::Boolean.new.cast(params[:was_queued])
  #   Rails.logger.info(job_id)
  #   Rails.logger.info(was_queued)
  #   if Sidekiq::Queue.new.find { |job| job.jib == job_id }.present?
  #     render json: { msg: "Queued" }, status: 202
  #   elsif Sidekiq::WorkSet.new.find_work_by_jid(job_id).present?
  #     render json: { msg: "Working" }, status: 202
  #   elsif was_queued
  #     render json: { msg: "Complete" }, status: 200
  #   else
  #     render json: { msg: "Not Found" }, status: 404
  #   end
  # end

  def verify_download_path(base_path, file_id)
    # User provided UUID to be used in a file path - verify things are OK
    download_path = build_download_path(base_path, file_id)
    if download_path.relative? # ensure file_id string is not a relative path
      false
    elsif file_id.include?(".") # ensure file_id string doesnt have any periods
      false
    elsif download_path.to_s.exclude?(base_path.to_s) # ensure the save_path results in something containing the base_path
      false
    else
      true
    end
  end

  def build_download_path(base_path, file_id)
    base_path.join(file_id.to_s + ".pdf")
  end
end
