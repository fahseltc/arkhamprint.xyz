require "open-uri"
require "prawn/measurement_extensions"
require "tempfile"
require "mini_magick"

# Prawn PDF origin location is at the bottom-left corner of the page (0,0)
# page still filled from top to bottom using the cursor - starts at the top
# The base unit in Prawn is the PDF Point. One PDF Point is equal to 1/72 of an inch.
# 1 inch in PDF Points: 72 pt
# 2.5 x 3.5 for standard card sizes so 180 pts x 252
# LETTER Page size 612.00 x 792.00   https://www.rubydoc.info/github/sandal/prawn/master/Prawn/Document/PageGeometry

module PdfHelper
  CARDS_PER_PAGE = 9
  CARD_WIDTH = 180.0   # 2.5in, in points - cards are drawn at this exact size
  CARD_HEIGHT = 252.0  # 3.5in, in points

  # Default white space left between adjacent cards on every side, so an
  # imprecise cut can't slice into the neighboring card. Callers may pass
  # gap: 0 to print cards edge-to-edge instead.
  DEFAULT_GAP = 2.mm
  NO_GAP = 0

  PAGE_WIDTH = 612.0  # LETTER, portrait, in points
  PAGE_HEIGHT = 792.0

  def self.generate(cards, page_size, gap: NO_GAP, job_id: nil)
    pdf = new_document(gap)
    positions = grid_positions(gap)
    total = cards.values.sum
    current_card = 0
    slot = 0

    Rails.logger.info("generating PDF with cards count #{total}")

    cards.each do |url, quantity|
      quantity.times do
        if slot > 0 && (slot % CARDS_PER_PAGE).zero?
          pdf.start_new_page
        end
        current_card += 1
        Rails.logger.info("Printing card #{current_card}/#{total} at slot #{slot % CARDS_PER_PAGE} page #{pdf.page_number}")
        draw_card(pdf, url, positions[slot % CARDS_PER_PAGE])
        yield(current_card)
        slot += 1
      end
    end

    tmp = Tempfile.new([ "pdf_job_#{job_id}_", ".pdf" ])
    begin
      pdf.render_file(tmp.path)
      tmp
    rescue
      tmp.close!
      raise
    end
  end

  # Draws a front page followed immediately by a back page for each group of
  # up to 9 cards, so a printshop can duplex-print front/back in one pass.
  # `records` is [{ front_url:, back_url:, quantity: }]. `duplex_mode` picks
  # which axis the back grid mirrors to match how the printshop's duplexer
  # physically flips the sheet - "none" (no mirroring, manual alignment),
  # "long_edge" (mirrors columns) or "short_edge" (mirrors rows).
  def self.generate_with_backs(records, page_size, duplex_mode: "none", gap: NO_GAP, job_id: nil)
    pdf = new_document(gap)
    positions = grid_positions(gap)
    total = records.sum { |r| r[:quantity] }
    current_card = 0

    Rails.logger.info("generating duplex PDF with cards count #{total}, duplex_mode=#{duplex_mode}")

    # Build chunks of up to CARDS_PER_PAGE without materializing the full
    # duplicated list — iterate quantities directly and flush each chunk as
    # soon as it's full or we've exhausted all records.
    chunk = []
    records.each do |record|
      record[:quantity].times do
        chunk << record
        next unless chunk.size == CARDS_PER_PAGE

        pdf.start_new_page if pdf.page_number > 1 || current_card > 0
        chunk.each_with_index do |r, slot|
          draw_card(pdf, r[:front_url], positions[slot])
          current_card += 1
          yield(current_card)
        end
        pdf.start_new_page
        chunk.each_with_index do |r, slot|
          draw_card(pdf, r[:back_url], positions[back_slot_for(slot, duplex_mode)])
          current_card += 1
          yield(current_card)
        end
        chunk = []
      end
    end

    # Flush any remaining cards that didn't fill a full page
    unless chunk.empty?
      pdf.start_new_page if pdf.page_number > 1 || current_card > 0
      chunk.each_with_index do |r, slot|
        draw_card(pdf, r[:front_url], positions[slot])
        current_card += 1
        yield(current_card)
      end
      pdf.start_new_page
      chunk.each_with_index do |r, slot|
        draw_card(pdf, r[:back_url], positions[back_slot_for(slot, duplex_mode)])
        current_card += 1
        yield(current_card)
      end
    end

    tmp = Tempfile.new([ "pdf_job_#{job_id}_", ".pdf" ])
    begin
      pdf.render_file(tmp.path)
      tmp
    rescue
      tmp.close!
      raise
    end
  end

  # 3x3 top-left corner positions for one page's cards, pitched by
  # CARD_WIDTH/HEIGHT plus the given gap (0 packs cards edge-to-edge).
  def self.grid_positions(gap)
    column_pitch = CARD_WIDTH + gap
    row_pitch = CARD_HEIGHT + gap
    grid_height = (3 * row_pitch) - gap
    (0...CARDS_PER_PAGE).map { |slot| [ (slot % 3) * column_pitch, grid_height - (slot / 3) * row_pitch ] }
  end

  # Margins derived from the grid+gap size (rather than fixed) so the 3x3
  # grid always fits fully inside the page: fixed 18/36pt margins left zero
  # vertical slack even with gap 0 (3 * CARD_HEIGHT == page height minus
  # margins exactly), so any gap pushed the bottom row off the printable area.
  def self.margins_for(gap)
    grid_width = (3 * (CARD_WIDTH + gap)) - gap
    grid_height = (3 * (CARD_HEIGHT + gap)) - gap
    [ (PAGE_WIDTH - grid_width) / 2, (PAGE_HEIGHT - grid_height) / 2 ]
  end

  # Maps a front grid slot (0-8, row-major) to the grid slot its back image
  # should be drawn at, per the duplex flip axis. See CARDS_PER_PAGE grid:
  # long_edge flip rotates the sheet about its long (vertical) edge, which
  # mirrors columns; short_edge flip rotates about its short (horizontal)
  # edge, which mirrors rows.
  def self.back_slot_for(front_slot, duplex_mode)
    row, col = front_slot.divmod(3)
    case duplex_mode
    when "long_edge" then col = 2 - col
    when "short_edge" then row = 2 - row
    end
    row * 3 + col
  end

  def self.new_document(gap)
    left_margin, top_margin = margins_for(gap)
    Prawn::Document.new(page_size: "LETTER", page_layout: :portrait,
                         top_margin: top_margin, bottom_margin: top_margin,
                         left_margin: left_margin, right_margin: left_margin)
  end

  # `source` is either a remote card image URL or a local card-back asset
  # path (see CardBackHelper). Skips the slot (logs a warning) if the image
  # can't be opened, same as the original inline behavior. Drawn at exactly
  # CARD_WIDTH x CARD_HEIGHT - GAP is spacing between slots (see
  # GRID_POSITIONS), not a change to the card itself.
  def self.draw_card(pdf, source, position)
    img = open_card_image(source)
    return unless img

    img.rotate(90) if img.width > img.height
    crop_to_card_ratio(img)
    Tempfile.create([ "card", ".png" ]) do |f|
      img.write(f.path)
      pdf.image f.path, width: CARD_WIDTH, height: CARD_HEIGHT, at: position
    end
  ensure
    img&.destroy! # explicitly frees ImageMagick memory
  end

  # Prawn's image placement above stretches to exactly CARD_WIDTH x
  # CARD_HEIGHT, non-uniformly if the source isn't quite 2.5:3.5 - card scans
  # are close enough for this to be a non-issue, but the generic card-back
  # art (CardBackHelper) is off enough to look subtly squashed. Center-crop
  # (never upscale) to the card's ratio first so that stretch is uniform.
  def self.crop_to_card_ratio(img)
    card_ratio = CARD_WIDTH / CARD_HEIGHT
    if img.width.to_f / img.height > card_ratio
      target_w = (img.height * card_ratio).round
      target_h = img.height
    else
      target_w = img.width
      target_h = (img.width / card_ratio).round
    end

    img.combine_options do |c|
      c.gravity "center"
      c.extent "#{target_w}x#{target_h}"
    end
  end

  def self.open_card_image(source)
    # Resolve remote URLs through the local disk cache to avoid redundant HTTP
    # fetches for the same card across jobs. Local asset paths (card backs) are
    # passed through unchanged — CardImageCache only handles http(s) URLs.
    resolved = source.start_with?("http") ? CardImageCache.fetch(source) : source
    return nil unless resolved

    MiniMagick::Image.open(resolved)
  rescue StandardError => e
    Rails.logger.warn("Failed to open #{source}: #{e.message}")
    nil
  end

  # doesnt really work in all cases
  def self.add_black_background(image)
    # Decide how big each corner region should be
    region_w = (image.width * 0.05).to_i
    region_h = (image.height * 0.05).to_i

    corners = [
      [ 0, 0 ],                                    # top-left
      [ image.width - region_w, 0 ],               # top-right
      [ 0, image.height - region_h ],              # bottom-left
      [ image.width - region_w, image.height - region_h ] # bottom-right
    ]

    # Make near-white in each corner region transparent
    corners.each do |x, y|
      image.combine_options do |c|
        c.fuzz "12%"
        c.region "#{region_w}x#{region_h}+#{x}+#{y}"
        c.transparent "white"
      end
    end

    # Flatten any transparency to black
    image.combine_options do |c|
      c.background "black"
      c.flatten
    end

    # Ensure no alpha remains
    image.format "png" do |c|
      c.alpha "off"
    end

    image
  end
end
