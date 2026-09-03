# Storage abstraction for generated PDFs.
#
# In production (config.pdf_storage_mode == :s3) PDFs are uploaded to S3 and
# served via short-lived presigned URLs. In development without AWS credentials
# (:local) PDFs are written to tmp/pdf_output/ and served directly by Rails, so
# contributors can run the whole PDF flow with no AWS setup at all.
#
# The mode is chosen at boot in config/application.rb based on whether
# AWS_BUCKET is set in the environment.
module PdfStorage
  BASE_KEY_PREFIX = "uploads/pdf/deck_".freeze
  LOCAL_DIR = Rails.root.join("tmp", "pdf_output")

  module_function

  def mode
    Rails.application.config.pdf_storage_mode
  end

  def local?
    mode == :local
  end

  # Stores the PDF for a job and returns the value to persist as file_url.
  #  - :s3    -> the S3 object key (e.g. "uploads/pdf/deck_<id>.pdf")
  #  - :local -> a local: sentinel path (e.g. "local:<id>.pdf")
  # `path` is the filesystem path of the finished PDF (a Tempfile path).
  def store(job_id, path)
    local? ? store_local(job_id, path) : store_s3(job_id, path)
  end

  # Given a stored file_url, returns something the controller can redirect to
  # or send. For :s3 this is a presigned URL string; for :local it's a local
  # filesystem path. Callers distinguish via `local?`.
  def retrieve_url(file_url)
    local? ? local_path_for(file_url) : presigned_url(file_url)
  end

  # ---- S3 backend --------------------------------------------------------

  def store_s3(job_id, path)
    require "aws-sdk-s3"
    s3_key = "#{BASE_KEY_PREFIX}#{job_id}.pdf"
    client = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION"))
    File.open(path, "rb") do |file|
      client.put_object(
        bucket: ENV.fetch("AWS_BUCKET"),
        key: s3_key,
        body: file,
        content_type: "application/pdf",
        acl: "private"
      )
    end
    s3_key
  end

  def presigned_url(s3_key)
    require "aws-sdk-s3"
    client = Aws::S3::Client.new(region: ENV.fetch("AWS_REGION"))
    Aws::S3::Presigner.new(client: client).presigned_url(
      :get_object,
      bucket: ENV.fetch("AWS_BUCKET"),
      key: s3_key,
      expires_in: 300
    )
  end

  # ---- Local backend -----------------------------------------------------

  def store_local(job_id, path)
    FileUtils.mkdir_p(LOCAL_DIR)
    filename = "#{job_id}.pdf"
    dest = LOCAL_DIR.join(filename)
    FileUtils.cp(path, dest)
    "local:#{filename}"
  end

  # Resolves a "local:<filename>" file_url to its absolute path on disk.
  def local_path_for(file_url)
    filename = file_url.sub(/\Alocal:/, "")
    # Guard against path traversal — only a bare filename is ever valid here.
    filename = File.basename(filename)
    LOCAL_DIR.join(filename).to_s
  end
end
