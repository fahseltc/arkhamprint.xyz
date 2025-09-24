class PdfJobsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token
  require "aws-sdk-s3"
  # Create a new PDF job
  def create
    pdf_job = PdfJob.create!(status: "pending")

    # Enqueue Sidekiq job
    jid = GeneratePdfFromDeckJob.perform_async(pdf_job.id, pdf_params)
    pdf_job.update!(job_jid: jid)

    render json: { pdf_job_id: pdf_job.id, status: pdf_job.status }
  end

  # Check the status of a PDF job
  def show
    pdf_job = PdfJob.find(params[:id])
    render json: pdf_job.slice(:id, :status, :file_url, :error_message)
  end

  # Download the generated PDF
  def download
    pdf_job = PdfJob.find(params[:id])

    if pdf_job.status != "completed" || pdf_job.file_url.blank?
      head :not_found
      return
    end

    if pdf_job.file_url.start_with?("http")
      # If the URL is already public, just redirect
      redirect_to pdf_job.file_url
    else
      # If using S3 with private bucket, generate a pre-signed URL
      s3_client = Aws::S3::Resource.new(region: ENV["AWS_REGION"])
      bucket = s3_client.bucket(ENV["AWS_BUCKET"])
      object = bucket.object(pdf_job.file_url) # file_url is S3 key/path

      # Generate a pre-signed URL valid for 5 minutes
      presigned_url = object.presigned_url(:get, expires_in: 300)

      redirect_to presigned_url, allow_other_host: true
    end
  end


  private

  # Permit the cards array from request parameters
  def pdf_params
    params.require(:deck_id)
  end
end
