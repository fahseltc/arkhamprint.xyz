class PdfJobsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    # Use Redis-backed PdfJob
    pdf_job = PdfJob.create!(status: "pending")
    jid = GeneratePdfFromDeckJob.perform_async(pdf_job.id, pdf_params)
    pdf_job.update!(job_jid: jid)

    render json: { pdf_job_id: pdf_job.id, status: pdf_job.status }
  end

  def show
    pdf_job = PdfJob.find(params[:id])
    render json: {
      id: pdf_job.id,
      status: pdf_job.status,
      file_url: pdf_job.file_url,
      error_message: pdf_job.error_message
    }
  end

  def download
    pdf_job = PdfJob.find(params[:id])
    if pdf_job.status != "completed"
      head :not_found and return
    end

    if pdf_job.file_url.start_with?("http")
      redirect_to pdf_job.file_url, allow_other_host: true
    else
      send_file pdf_job.file_url, type: "application/pdf", filename: "document.pdf"
    end
  end

  private

  def pdf_params
    params.require(:deck_id)
  end
end
