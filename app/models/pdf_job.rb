require "redis"
require "securerandom"
require "json"

class PdfJob
  attr_accessor :id, :status, :file_url, :error_message, :job_jid, :current_progress, :max_progress


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
    case Rails.application.config.save_data_mode
    when :redis
      data = redis.hgetall(redis_key(id))
      raise "PdfJob not found" if data.empty?

    when :file
      file_path = Rails.root.join("tmp", "jobdata", "#{id}.json")
      # Rails.logger.info("Trying to open file: #{file_path}")
      raise "PdfJob not found" unless File.exist?(file_path)

      data = JSON.parse(File.read(file_path))
    else
      raise "Unknown save_data_mode: #{Rails.application.config.save_data_mode.inspect}"
    end

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
    case Rails.application.config.save_data_mode
    when :redis
      self.class.redis.hmset(self.class.redis_key(id), *data.to_a.flatten)
    when :file
      require "json"
      dir_path = Rails.root.join("tmp", "jobdata")
      FileUtils.mkdir_p(dir_path)  unless Dir.exist?(dir_path)

      file_path = dir_path.join("#{id}.json")
      # Rails.logger.info("Saving file #{file_path}...")

      File.atomic_write(file_path) do |f|
        f.write(JSON.pretty_generate(data))
      end
    end
  end

  def delete!
    case Rails.application.config.save_data_mode
    when :redis
      self.class.redis.del(self.class.redis_key(id))

    when :file
      file_path = Rails.root.join("tmp", "jobdata", "#{id}.json")
      File.delete(file_path) if File.exist?(file_path)
    else
      raise "Unknown save_data_mode: #{Rails.application.config.save_data_mode.inspect}"
    end
  end

  private

  def self.redis_key(id)
    "pdf_job:#{id}"
  end

  def self.redis
    @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end
end
