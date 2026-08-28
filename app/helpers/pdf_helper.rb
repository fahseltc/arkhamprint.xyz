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

  # White space left between adjacent cards on every side, so an imprecise
  # cut can't slice into the neighboring card.
  GAP = 2.mm
  COLUMN_PITCH = CARD_WIDTH + GAP
  ROW_PITCH = CARD_HEIGHT + GAP

  PAGE_WIDTH = 612.0  # LETTER, portrait, in points
  PAGE_HEIGHT = 792.0

  GRID_WIDTH = (3 * COLUMN_PITCH) - GAP  # 3 cards + 2 gaps between them (no trailing gap)
  GRID_HEIGHT = (3 * ROW_PITCH) - GAP

  # Margins are derived from GRID_WIDTH/HEIGHT (rather than fixed) so the
  # 3x3 grid - cards plus their gaps - always fits fully inside the page:
  # the original fixed 18/36pt margins left zero vertical slack even before
  # GAP existed (3 * CARD_HEIGHT == page height minus margins exactly), so
  # any gap pushed the bottom row past the margin and off the printable area.
  LEFT_MARGIN = (PAGE_WIDTH - GRID_WIDTH) / 2
  TOP_MARGIN = (PAGE_HEIGHT - GRID_HEIGHT) / 2

  GRID_POSITIONS = (0...CARDS_PER_PAGE).map { |slot| [ (slot % 3) * COLUMN_PITCH, GRID_HEIGHT - (slot / 3) * ROW_PITCH ] }

  def self.generate(cards, page_size)
    pdf = new_document
    instances = cards.flat_map { |url, quantity| Array.new(quantity, url) }
    current_card = 0

    Rails.logger.info("generating PDF with cards count #{instances.size}")

    instances.each_slice(CARDS_PER_PAGE).with_index do |chunk, page_index|
      pdf.start_new_page if page_index.positive?
      chunk.each_with_index do |url, slot|
        current_card += 1
        Rails.logger.info("Printing card #{current_card}/#{instances.size} at slot #{slot} page #{pdf.page_number}")
        draw_card(pdf, url, GRID_POSITIONS[slot])
        yield(current_card)
      end
    end

    pdf.render
  end

  # Draws a front page followed immediately by a back page for each group of
  # up to 9 cards, so a printshop can duplex-print front/back in one pass.
  # `records` is [{ front_url:, back_url:, quantity: }]. `duplex_mode` picks
  # which axis the back grid mirrors to match how the printshop's duplexer
  # physically flips the sheet - "none" (no mirroring, manual alignment),
  # "long_edge" (mirrors columns) or "short_edge" (mirrors rows).
  def self.generate_with_backs(records, page_size, duplex_mode: "none")
    pdf = new_document
    instances = records.flat_map { |r| Array.new(r[:quantity], r) }
    current_card = 0

    Rails.logger.info("generating duplex PDF with cards count #{instances.size}, duplex_mode=#{duplex_mode}")

    instances.each_slice(CARDS_PER_PAGE).with_index do |chunk, page_index|
      pdf.start_new_page if page_index.positive?
      chunk.each_with_index do |record, slot|
        draw_card(pdf, record[:front_url], GRID_POSITIONS[slot])
        current_card += 1
        yield(current_card)
      end

      pdf.start_new_page
      chunk.each_with_index do |record, slot|
        draw_card(pdf, record[:back_url], GRID_POSITIONS[back_slot_for(slot, duplex_mode)])
        current_card += 1
        yield(current_card)
      end
    end

    pdf.render
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

  def self.new_document
    Prawn::Document.new(page_size: "LETTER", page_layout: :portrait,
                         top_margin: TOP_MARGIN, bottom_margin: TOP_MARGIN,
                         left_margin: LEFT_MARGIN, right_margin: LEFT_MARGIN)
  end

  # `source` is either a remote card image URL or a local card-back asset
  # path (see CardBackHelper). Skips the slot (logs a warning) if the image
  # can't be opened, same as the original inline behavior. Drawn at exactly
  # CARD_WIDTH x CARD_HEIGHT, unmodified from the source - GAP is spacing
  # between slots (see GRID_POSITIONS), not a change to the card itself.
  def self.draw_card(pdf, source, position)
    img = open_card_image(source)
    return unless img

    img.rotate(90) if img.width > img.height
    Tempfile.create([ "card", ".png" ]) do |f|
      img.write(f.path)
      pdf.image f.path, width: CARD_WIDTH, height: CARD_HEIGHT, at: position
    end
  end

  def self.open_card_image(source)
    MiniMagick::Image.open(source)
  rescue OpenURI::HTTPError => e
    begin
      # Try again with JPG
      MiniMagick::Image.open(source.gsub(".png", ".jpg"))
    rescue OpenURI::HTTPError => e2
      Rails.logger.warn("Failed to open #{source}: #{e2.message} with either PNG or JPG")
      nil
    end
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
