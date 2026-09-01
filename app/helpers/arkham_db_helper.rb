module ArkhamDbHelper
  # In-process cache for card metadata. ArkhamDB card data is immutable once
  # published so this never needs invalidation — it persists for the lifetime
  # of the process. Keyed by card_id string, values are a hash:
  #   { double_sided: bool, back_image_url: String|nil, faction_code: String }
  # Mutex protects against concurrent threads populating the same entry.
  CARD_META_CACHE = {}
  CARD_META_MUTEX = Mutex.new

  def self.get_cards_from_deck_id(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    response = HTTParty.get(decklist_api + deck_id.to_s)

    # Extract only what's needed before dropping the response object
    slots = response["slots"].compact.reject { |id, _quantity| id == "01000" }
    investigator_code = response["investigator_code"]
    response = nil # allow GC to reclaim the full parsed response body

    # Always include the investigator card. It's double-sided, so we add only
    # the front id once — the back side is resolved automatically via the
    # card's `double_sided`/`backimagesrc` metadata (see resolve_back_url).
    # Adding a separate `#{code}b` entry here would double-print the back.
    cards = investigator_code ? { investigator_code => 1 }.merge(slots) : slots

    Rails.logger.info(cards)
    cards
  end

  def self.get_card(card_id)
    card_api = "https://arkhamdb.com/api/public/card/"
    response = HTTParty.get(card_api + card_id.to_s)
    if response.code == 200
      response
    else
      Rails.logger.error("error when trying to collect card with ID #{card_id}")
      nil
    end
  end

  # Returns back-side information for a card, using a process-level cache so
  # repeated jobs never re-fetch the same card. Falls back gracefully if the
  # API is unreachable.
  #
  # Returns:
  #   {
  #     double_sided:    true | false,
  #     back_image_url:  "https://arkhamdb.com/bundles/cards/01001b.png" | nil,
  #     faction_code:    "guardian" | "mythos" | etc.
  #   }
  def self.get_card_back_info(card_id)
    # Fast path — already cached
    cached = CARD_META_CACHE[card_id]
    return cached if cached

    CARD_META_MUTEX.synchronize do
      # Re-check inside the lock in case another thread populated it first
      return CARD_META_CACHE[card_id] if CARD_META_CACHE[card_id]

      Rails.logger.debug("CardMetaCache miss: #{card_id}")
      response = get_card(card_id)

      meta = if response
        double_sided   = response["double_sided"] == true
        raw_back_src   = response["backimagesrc"]
        back_image_url = if double_sided && raw_back_src.present?
          "https://arkhamdb.com#{raw_back_src}"
        end
        {
          double_sided:   double_sided,
          back_image_url: back_image_url,
          faction_code:   response["faction_code"].to_s
        }
      else
        # API error — store a safe fallback so we don't hammer a broken endpoint
        { double_sided: false, back_image_url: nil, faction_code: "neutral" }
      end

      CARD_META_CACHE[card_id] = meta
      meta
    end
  end

  # Pre-fetches metadata for many cards concurrently so the per-card
  # resolve_back_url calls that follow all hit the warm cache instantly.
  # The API calls are IO-bound (waiting on ArkhamDB), so running them in a
  # bounded thread pool collapses N serial round-trips into roughly the time
  # of the slowest single call.
  #
  # Yields (completed_count, total_count) after each fetch if a block is given,
  # so callers can drive a progress indicator during the warm-up phase.
  def self.warm_card_meta_cache(card_ids, max_threads: 8)
    uncached = card_ids.uniq.reject { |id| CARD_META_CACHE.key?(id) }
    total    = uncached.size
    return if total.zero?

    Rails.logger.info("Warming card meta cache: #{total} uncached card(s)")
    completed = 0
    completed_mutex = Mutex.new
    queue = Queue.new
    uncached.each { |id| queue << id }

    workers = Array.new([ max_threads, total ].min) do
      Thread.new do
        until queue.empty?
          card_id = queue.pop(true) rescue nil
          break unless card_id
          get_card_back_info(card_id) # populates CARD_META_CACHE
          completed_mutex.synchronize do
            completed += 1
            yield(completed, total) if block_given?
          end
        end
      end
    end
    workers.each(&:join)
    Rails.logger.info("Card meta cache warmed: #{total} card(s)")
  end

  # Resolves the correct back image URL for a card:
  #   - If the card is double-sided, returns the ArkhamDB back image URL
  #   - Otherwise returns the local faction card-back asset path
  def self.resolve_back_url(card_id)
    meta = get_card_back_info(card_id)
    if meta[:double_sided] && meta[:back_image_url]
      meta[:back_image_url]
    else
      CardBackHelper.path_for(meta[:faction_code])
    end
  end

  def self.get_card_image_url(card_id)
    "https://arkhamdb.com/bundles/cards/" + card_id + ".png"
  end

  def self.get_all_cards
    HTTParty.get("https://arkhamdb.com/api/public/cards/")
  end
end
