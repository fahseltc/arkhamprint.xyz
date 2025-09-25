require "redis"
require "securerandom"

class PdfJob
  attr_accessor :id, :status, :file_url, :error_message, :job_jid, :current_progress, :max_progress

  REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))

  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @status = attributes[:status] || "pending"
    @file_url = attributes[:file_url]
    @error_message = attributes[:error_message]
    @job_jid = attributes[:job_jid]
    @current_progress = attributes[:current_progress] || 0
    @max_progress = attributes[:max_progress] || 0
  end

  def self.create!(attributes = {})
    job = new(attributes)
    job.save!
    job
  end

  def self.find(id)
    data = REDIS.hgetall(redis_key(id))
    raise "PdfJob not found" if data.empty?

    new(
      id: id,
      status: data["status"],
      file_url: data["file_url"],
      error_message: data["error_message"],
      job_jid: data["job_jid"],
      current_progress: data["current_progress"].to_i,
      max_progress: data["max_progress"].to_i
    )
  end

  def update!(attributes = {})
    attributes.each do |k, v|
      send("#{k}=", v) if respond_to?("#{k}=")
    end
    save!
  end

  def save!
    data = {
      "status" => status || "",
      "file_url" => file_url || "",
      "error_message" => error_message || "",
      "job_jid" => job_jid || "",
      "current_progress" => current_progress || 0,
      "max_progress" => max_progress || 0
    }
    REDIS.hmset(self.class.redis_key(id), *data.to_a.flatten)
  end

  private

  def self.redis_key(id)
    "pdf_job:#{id}"
  end
end
