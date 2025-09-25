require "redis"
require "securerandom"

class PdfJob
  attr_accessor :id, :status, :file_url, :error_message, :job_jid

  # Class-level Redis connection
  REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))

  # Initialize a new PdfJob object
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @status = attributes[:status] || "pending"
    @file_url = attributes[:file_url]
    @error_message = attributes[:error_message]
    @job_jid = attributes[:job_jid]
  end

  # Create a new job and store it in Redis
  def self.create!(attributes = {})
    job = new(attributes)
    job.save!
    job
  end

  # Find an existing job by ID
  def self.find(id)
    data = REDIS.hgetall(redis_key(id))
    raise "PdfJob not found" if data.empty?

    new(
      id: id,
      status: data["status"],
      file_url: data["file_url"],
      error_message: data["error_message"],
      job_jid: data["job_jid"]
    )
  end

  # Update attributes and persist to Redis
  def update!(attributes = {})
    attributes.each do |k, v|
      send("#{k}=", v) if respond_to?("#{k}=")
    end
    save!
  end

  # Persist the job to Redis
  def save!
    data = {
      "status" => status || "",
      "file_url" => file_url || "",
      "error_message" => error_message || "",
      "job_jid" => job_jid || ""
    }
    REDIS.hmset(self.class.redis_key(id), *data.to_a.flatten)
  end

  private

  # Redis key for this job
  def self.redis_key(id)
    "pdf_job:#{id}"
  end
end
