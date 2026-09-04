class GeneratePdfFromDeckJob < GeneratePdfBaseJob
  def parse_params
    @deck_id = @pdf_params["deck_id"]
    raise ArgumentError, "deck_id must be present" unless @deck_id.present?
  end

  def generate_pdf_bin
    # cards_hash is { front_image_url => quantity }
    cards_hash = get_cards_hash

    if @print_backs
      total_images = cards_hash.values.sum * 2
      Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{cards_hash.values.sum} duplex=true duplex_mode=#{@duplex_mode}")
      records = build_records_with_backs(cards_hash, total_images)
      PdfHelper.generate_with_backs(records, "LETTER", duplex_mode: @duplex_mode, gap: @gap, bleed: @bleed, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    else
      # Front-only print. The investigator card is double-sided and its reverse
      # is real card content (stats/setup), not a decorative back — so include
      # it as its own front-facing card even though backs are off.
      cards_hash = add_investigator_back_as_front(cards_hash)
      total_images = cards_hash.values.sum
      Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{total_images} duplex=false")
      @pdf_job.update!(max_progress: total_images, current_progress: 0)
      PdfHelper.generate(cards_hash, "LETTER", gap: @gap, bleed: @bleed, job_id: @pdf_job.id) do |idx|
        report_progress(idx)
      end
    end
  end

  def get_cards_hash
    deck = ArkhamDbHelper.fetch_deck(@deck_id)
    @investigator_code = deck[:investigator_code]

    # deck_cards is { card_id => quantity }. Add any bonded cards (set aside by
    # the Dream-Eaters mechanic) whose parent is present in the deck — ArkhamDB's
    # deck API never lists these. Uses the static config/bonded_cards.json index.
    deck_cards = deck[:cards].dup
    ArkhamDbHelper.bonded_cards_for(deck_cards.keys).each do |bonded_id, qty|
      deck_cards[bonded_id] = (deck_cards[bonded_id] || 0) + qty
    end

    cards = deck_cards.transform_keys { |card_id| ArkhamDbHelper.get_card_image_url(card_id) }
    Rails.logger.info(cards)
    cards
  end

  # Inserts the investigator's back-side image as a standalone front card,
  # positioned immediately after the investigator's front so the two halves of
  # the sheet print next to each other. This lets the reverse of the
  # investigator sheet still print when card backs are off. No-op if there's no
  # investigator or it has no distinct back.
  def add_investigator_back_as_front(cards_hash)
    return cards_hash unless @investigator_code

    meta = ArkhamDbHelper.get_card_back_info(@investigator_code)
    return cards_hash unless meta[:double_sided] && meta[:back_image_url]

    front_url = ArkhamDbHelper.get_card_image_url(@investigator_code)
    back_url  = meta[:back_image_url]

    # Rebuild the hash so back_url sits directly after front_url, preserving the
    # order of every other card. (Ruby hashes keep insertion order.)
    rebuilt = {}
    cards_hash.each do |url, qty|
      rebuilt[url] = qty
      if url == front_url
        rebuilt[back_url] = (rebuilt[back_url] || 0) + 1
      end
    end
    # If the investigator front wasn't in the deck for some reason, fall back to
    # appending the back so it still prints.
    rebuilt[back_url] = (rebuilt[back_url] || 0) + 1 unless rebuilt.key?(back_url)

    Rails.logger.info("Inserted investigator back after front: #{back_url}")
    rebuilt
  end
end
