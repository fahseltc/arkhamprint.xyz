module ArkhamDbHelper
  # In-process cache for card metadata. ArkhamDB card data is immutable once
  # published so this never needs invalidation — it persists for the lifetime
  # of the process. Keyed by card_id string, values are a hash:
  #   { double_sided: bool, back_image_url: String|nil, faction_code: String }
  # Mutex protects against concurrent threads populating the same entry.
  CARD_META_CACHE = {}
  CARD_META_MUTEX = Mutex.new

  # Returns { cards: { card_id => quantity }, investigator_code: String|nil }.
  # The investigator card is always included in cards (added once as its front
  # id; its back is resolved via double_sided metadata — see resolve_back_url).
  def self.fetch_deck(deck_id)
    decklist_api = "https://arkhamdb.com/api/public/decklist/"
    response = HTTParty.get(decklist_api + deck_id.to_s)

    # Extract only what's needed before dropping the response object
    slots = response["slots"].compact.reject { |id, _quantity| id == "01000" }
    investigator_code = response["investigator_code"]
    response = nil # allow GC to reclaim the full parsed response body

    cards = investigator_code ? { investigator_code => 1 }.merge(slots) : slots

    { cards: cards, investigator_code: investigator_code }
  end

  # Backwards-compatible accessor returning only the { card_id => quantity } hash.
  def self.get_cards_from_deck_id(deck_id)
    cards = fetch_deck(deck_id)[:cards]
    Rails.logger.info(cards)
    cards
  end

  # --- Scenario index -------------------------------------------------------
  #
  # scenarios.json is static bundled config (the campaign/scenario dropdown
  # index). It's read on every home page load and every scenario job, so parse
  # it once and memoize for the process lifetime rather than re-reading from
  # disk each time.
  SCENARIOS_PATH = Rails.root.join("scenarios.json")

  def self.scenarios_index
    @scenarios_index ||= JSON.parse(File.read(SCENARIOS_PATH))
  end

  # --- Bonded cards ---------------------------------------------------------
  #
  # "Bonded" cards (Dream-Eaters mechanic) are set aside with a deck rather than
  # listed in it, so ArkhamDB's deck API never returns them. The card DB also
  # only links one way (a bonded card knows its parent, not vice versa), so
  # there's no live query for "what does this deck card bond to". Instead we ship
  # a static index generated from the full card list, keyed by PARENT card code:
  #   { "05313" => [ { "code" => "05314", "quantity" => 3, "name" => "..." } ] }
  # Regenerate it with `rake bonded:refresh` when new bonded cards release.
  BONDED_CARDS_PATH = Rails.root.join("config", "bonded_cards.json")

  # Given a deck's card ids, returns { bonded_card_id => quantity } for every
  # bonded card whose parent is present in the deck. Empty hash if none.
  def self.bonded_cards_for(card_ids)
    index = bonded_index
    return {} if index.empty?

    result = Hash.new(0)
    card_ids.each do |code|
      Array(index[code]).each do |bonded|
        result[bonded["code"]] += bonded["quantity"].to_i
      end
    end

    Rails.logger.info("Bonded cards resolved: #{result}") unless result.empty?
    result
  end

  # Loads and memoizes the static bonded-card index. Returns {} if the file is
  # missing or unreadable, so a bonded lookup is a silent no-op rather than
  # breaking PDF generation.
  def self.bonded_index
    return @bonded_index if defined?(@bonded_index) && @bonded_index

    @bonded_index =
      begin
        JSON.parse(File.read(BONDED_CARDS_PATH))
      rescue StandardError => e
        Rails.logger.warn("Could not load bonded_cards.json: #{e.message}; bonded cards will be skipped")
        {}
      end
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
