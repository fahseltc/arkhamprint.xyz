require "uri"
require "open-uri"

module CardImageCache
  CACHE_DIR = Rails.root.join("tmp", "card_image_cache")
  # Images older than this are considered stale and re-fetched on next use.
  # ArkhamDB card art is essentially permanent, so 30 days is conservative.
  MAX_AGE = 90.days

  # Returns a local filesystem path for the given remote image URL, fetching
  # and caching it if not already present. Returns nil if the image can't be
  # fetched (same contract as PdfHelper.open_card_image).
  def self.fetch(url)
    FileUtils.mkdir_p(CACHE_DIR)
    cache_path = path_for(url)

    if cache_hit?(cache_path)
      Rails.logger.info("CardImageCache hit: #{cache_path.basename}")
      return cache_path.to_s
    end

    Rails.logger.info("CardImageCache miss: #{url}")
    download_to_cache(url, cache_path)
  end

  # Local path this URL maps to. Public so callers can check existence cheaply.
  def self.path_for(url)
    filename = File.basename(URI.parse(url).path)
    CACHE_DIR.join(filename)
  end

  # Remove cached images older than MAX_AGE. Called by the cleanup cron job.
  def self.prune_stale
    return unless Dir.exist?(CACHE_DIR)

    pruned = 0
    Dir.glob(CACHE_DIR.join("*")).each do |file|
      if File.mtime(file) < MAX_AGE.ago
        File.delete(file)
        pruned += 1
      end
    end
    Rails.logger.info("CardImageCache pruned #{pruned} stale file(s)")
  end

  private

  def self.cache_hit?(path)
    File.exist?(path) && File.mtime(path) > MAX_AGE.ago
  end

  # Writes to a .tmp sidecar first, then atomically renames so concurrent
  # threads never read a partially-written file.
  def self.download_to_cache(url, cache_path)
    tmp_path = Pathname.new("#{cache_path}.tmp")

    URI.open(url, read_timeout: 15) do |remote|  # rubocop:disable Security/Open
      tmp_path.binwrite(remote.read)
    end

    File.rename(tmp_path, cache_path)
    cache_path.to_s
  rescue OpenURI::HTTPError => e
    # Try .jpg fallback (same logic as open_card_image)
    if url.end_with?(".png")
      jpg_url = url.sub(/\.png$/, ".jpg")
      jpg_path = path_for(jpg_url)
      return download_to_cache(jpg_url, jpg_path)
    end
    Rails.logger.warn("CardImageCache failed to fetch #{url}: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.warn("CardImageCache error for #{url}: #{e.message}")
    nil
  ensure
    tmp_path.delete if tmp_path.exist? rescue nil
  end
end
