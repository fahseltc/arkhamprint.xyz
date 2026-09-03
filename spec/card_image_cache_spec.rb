require "rails_helper"

RSpec.describe "CardImageCache" do
  let(:url) { "https://arkhamdb.com/bundles/cards/01025.png" }
  let(:cache_path) { CardImageCache.path_for(url) }

  # Keep the real cache dir clean between examples: remove just the file(s) this
  # spec touches so we always exercise the miss-then-hit path deterministically.
  before { FileUtils.rm_f(cache_path) }
  after  { FileUtils.rm_f(cache_path) }

  describe ".path_for" do
    it "maps a remote URL to a local path inside the cache dir" do
      expect(cache_path.to_s).to start_with(CardImageCache::CACHE_DIR.to_s)
      expect(File.basename(cache_path)).to eq("01025.png")
    end
  end

  describe ".fetch" do
    it "downloads the image on a miss and writes it to the cache path" do
      # Stub the network read so the test doesn't depend on ArkhamDB.
      fake_bytes = "PNGDATA"
      allow(URI).to receive(:open).and_yield(StringIO.new(fake_bytes))

      returned = CardImageCache.fetch(url)

      expect(returned).to eq(cache_path.to_s)
      expect(File.exist?(cache_path)).to be true
      expect(File.binread(cache_path)).to eq(fake_bytes)
    end

    it "serves from disk on a second call without downloading again (cache hit)" do
      # First call: one download populates the cache.
      allow(URI).to receive(:open).and_yield(StringIO.new("PNGDATA"))
      CardImageCache.fetch(url)

      # Second call must NOT open the network again.
      expect(URI).not_to receive(:open)
      returned = CardImageCache.fetch(url)

      expect(returned).to eq(cache_path.to_s)
    end

    it "returns nil when the download fails" do
      allow(URI).to receive(:open).and_raise(StandardError.new("boom"))
      expect(CardImageCache.fetch(url)).to be_nil
    end
  end

  describe ".prune_stale" do
    it "deletes cached files older than MAX_AGE and keeps fresh ones" do
      FileUtils.mkdir_p(CardImageCache::CACHE_DIR)
      stale = CardImageCache::CACHE_DIR.join("stale_test.png")
      fresh = CardImageCache::CACHE_DIR.join("fresh_test.png")
      File.binwrite(stale, "x")
      File.binwrite(fresh, "x")
      # Backdate the stale file well past MAX_AGE. File.utime needs a plain Time.
      old = (CardImageCache::MAX_AGE + 1.day).ago.to_time
      File.utime(old, old, stale)

      CardImageCache.prune_stale

      expect(File.exist?(stale)).to be false
      expect(File.exist?(fresh)).to be true
    ensure
      FileUtils.rm_f(stale)
      FileUtils.rm_f(fresh)
    end
  end
end
