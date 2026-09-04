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
  rescue RuntimeError => e
    render json: { status: "failed", error_message: "Job not found" }, status: :not_found
  end

  # Cancel a running PDF job. Cooperative: flips the stored status, and the
  # running job notices it on its next progress update (see
  # GeneratePdfBaseJob#report_progress) and stops.
  def cancel
    pdf_job = PdfJob.find(safe_id_param)
    pdf_job.update!(status: "cancelled") unless pdf_job.status.in?(%w[completed failed cancelled])
    render json: { id: pdf_job.id, status: pdf_job.status }
  rescue RuntimeError
    render json: { status: "failed", error_message: "Job not found" }, status: :not_found
  end

  # Download the generated PDF. Serves from local disk in dev (no AWS) or via
  # a presigned S3 URL in production — see PdfStorage.
  def download
    pdf_job = PdfJob.find(safe_id_param)

    return head :not_found unless pdf_job.status == "completed"

    file_url = pdf_job.file_url

    if file_url.start_with?("http")
      # Absolute URL already (e.g. legacy records) — redirect straight to it.
      redirect_to file_url, allow_other_host: true
    elsif file_url.start_with?("local:")
      # Local dev storage — stream the file straight off disk.
      path = PdfStorage.local_path_for(file_url)
      return head :not_found unless File.exist?(path)
      send_file path, type: "application/pdf", disposition: "attachment",
                      filename: "arkhamprint_#{pdf_job.id}.pdf"
    else
      # S3 object key — hand back a short-lived presigned URL.
      redirect_to PdfStorage.presigned_url(file_url), allow_other_host: true
    end
  rescue RuntimeError
    head :not_found
  end

  private

  def pdf_params
    params.permit(:deck_id, :scenario_title, :campaign_file, :duplex_mode, :print_backs, :card_spacing, :cut_marks, card_ids: [])
  end

  def safe_id_param
    # only allow alphanumeric, underscore, dash
    raw = params[:id].to_s
    sanitized = raw.gsub(/[^a-zA-Z0-9_\-]/, "")
    raise ActionController::BadRequest, "Invalid ID" if sanitized.blank?
    sanitized
  end
end
