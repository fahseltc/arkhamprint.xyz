class PdfJobsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Create a new PDF job
  def create
    pdf_job = PdfJob.create!(status: "pending")
    if pdf_params["card_ids"].present?
      job = GeneratePdfFromCardListJob.perform_later(pdf_job.id, pdf_params)
    elsif pdf_params["scenario_title"].present?
      job = GeneratePdfFromScenarioJob.perform_later(pdf_job.id, pdf_params)
    else
      job = GeneratePdfFromDeckJob.perform_later(pdf_job.id, pdf_params)
    end

    Rails.logger.info("Job ID: #{job.job_id}, PDFJobID: #{pdf_job.id}, file saved at #{pdf_job.id}.json")
    pdf_job.update!(job_jid: job.job_id)

    render json: { pdf_job_id: pdf_job.id, status: pdf_job.status }
  end

  # Check the status of a PDF job
  def show
    pdf_job = PdfJob.find(safe_id_param)

    render json: {
      id: pdf_job.id,
      status: pdf_job.status,
      file_url: pdf_job.file_url,
      error_message: pdf_job.error_message,
      current_progress: pdf_job.current_progress || 0,
      max_progress: pdf_job.max_progress || 0
    }
  end

  # Download the generated PDF
  def download
    pdf_job = PdfJob.find(safe_id_param)

    return head :not_found unless pdf_job.status == "completed"

    if pdf_job.file_url.start_with?("http")
      redirect_to pdf_job.file_url, allow_other_host: true
    else
      # Generate a presigned S3 URL
      s3 = Aws::S3::Resource.new(region: ENV.fetch("AWS_REGION"))
      bucket = s3.bucket(ENV.fetch("AWS_BUCKET"))
      object = bucket.object(pdf_job.file_url)

      presigned_url = object.presigned_url(:get, expires_in: 300) # 5 minutes
      redirect_to presigned_url, allow_other_host: true
    end

    pdf_job.delete!
  end

  private

  def pdf_params
    params.permit(:deck_id, :include_investigator, :scenario_title, card_ids: [])
  end

  def safe_id_param
    # only allow alphanumeric, underscore, dash
    raw = params[:id].to_s
    sanitized = raw.gsub(/[^a-zA-Z0-9_\-]/, "")
    raise ActionController::BadRequest, "Invalid ID" if sanitized.blank?
    sanitized
  end
end
