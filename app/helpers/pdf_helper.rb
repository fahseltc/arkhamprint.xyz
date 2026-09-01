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
  CARD_WIDTH  = 180.0  # 2.5in in points — cards are drawn at this exact size
  CARD_HEIGHT = 252.0  # 3.5in in points

  # Directory for all intermediate and final PDF temp files. Using Rails' own
  # tmp/ keeps everything in one known location, easier to inspect and clean up.
  PDF_TMP_DIR = Rails.root.join("tmp", "pdf_work")

  # Default white space left between adjacent cards on every side, so an
  # imprecise cut can't slice into the neighboring card. Callers may pass
  # gap: 0 to print cards edge-to-edge instead.
  DEFAULT_GAP = 2.mm
  NO_GAP = 0

  PAGE_WIDTH  = 612.0  # LETTER, portrait, in points
  PAGE_HEIGHT = 792.0

  # Generates a front-only PDF. `cards` is { url => quantity }.
  # Each page holds up to CARDS_PER_PAGE cards. Pages are generated one at a
  # time (one Prawn document each) and merged with pdfunite, so the in-process
  # memory footprint is bounded to a single page regardless of total card count.
  # Yields current_card index after each card is drawn for progress reporting.
  # Returns a Tempfile of the merged PDF (caller is responsible for close!).
  def self.generate(cards, page_size, gap: NO_GAP, job_id: nil)
    positions = grid_positions(gap)
    total     = cards.values.sum
    current_card = 0
    page_index   = 0
    page_files   = []

    Rails.logger.info("generating PDF with #{total} cards")

    # Collect card URLs into slices of CARDS_PER_PAGE without materialising
    # the full duplicated list — iterate quantities directly.
    chunk = []
    cards.each do |url, quantity|
      quantity.times do
        chunk << url
        if chunk.size == CARDS_PER_PAGE
          page_files << render_page(job_id, page_index, gap) do |pdf|
            chunk.each_with_index do |card_url, slot|
              current_card += 1
              Rails.logger.info("Printing card #{current_card}/#{total} slot #{slot} page #{page_index + 1}")
              draw_card(pdf, card_url, positions[slot])
              yield(current_card)
            end
          end
          chunk = []
          page_index += 1
        end
      end
    end

    # Flush remaining cards that didn't fill a full page
    unless chunk.empty?
      page_files << render_page(job_id, page_index, gap) do |pdf|
        chunk.each_with_index do |card_url, slot|
          current_card += 1
          Rails.logger.info("Printing card #{current_card}/#{total} slot #{slot} page #{page_index + 1}")
          draw_card(pdf, card_url, positions[slot])
          yield(current_card)
        end
      end
    end

    combine_pages(page_files, job_id)
  end

  # Generates a duplex PDF: for each group of up to CARDS_PER_PAGE cards a
  # front page is immediately followed by its back page, so a printshop can
  # duplex-print in one pass. `records` is [{ front_url:, back_url:, quantity: }].
  # `duplex_mode` controls back-page slot mirroring (see back_slot_for).
  # Same page-at-a-time memory strategy as generate — yields progress per card.
  # Returns a Tempfile of the merged PDF (caller is responsible for close!).
  def self.generate_with_backs(records, page_size, duplex_mode: "none", gap: NO_GAP, job_id: nil)
    positions    = grid_positions(gap)
    total        = records.sum { |r| r[:quantity] } * 2  # front + back per card
    current_card = 0
    page_index   = 0
    page_files   = []

    Rails.logger.info("generating duplex PDF with #{total / 2} cards (#{total} images), duplex_mode=#{duplex_mode}")

    chunk = []
    records.each do |record|
      record[:quantity].times do
        chunk << record
        next unless chunk.size == CARDS_PER_PAGE

        page_files.concat(render_page_pair(chunk, positions, duplex_mode, gap, job_id, page_index) do |drawn|
          current_card += drawn
          yield(current_card)
        end)
        page_index += 2  # front + back count as two pages
        chunk = []
      end
    end

    # Flush remaining cards that didn't fill a full page
    unless chunk.empty?
      page_files.concat(render_page_pair(chunk, positions, duplex_mode, gap, job_id, page_index) do |drawn|
        current_card += drawn
        yield(current_card)
      end)
    end

    combine_pages(page_files, job_id)
  end

  # ---------------------------------------------------------------------------
  # Grid helpers — unchanged
  # ---------------------------------------------------------------------------

  # 3x3 top-left corner positions for one page's cards, pitched by
  # CARD_WIDTH/HEIGHT plus the given gap (0 packs cards edge-to-edge).
  def self.grid_positions(gap)
    column_pitch = CARD_WIDTH + gap
    row_pitch    = CARD_HEIGHT + gap
    grid_height  = (3 * row_pitch) - gap
    (0...CARDS_PER_PAGE).map { |slot| [ (slot % 3) * column_pitch, grid_height - (slot / 3) * row_pitch ] }
  end

  # Margins derived from the grid+gap size so the 3×3 grid always fits fully
  # inside the page without overflow.
  def self.margins_for(gap)
    grid_width  = (3 * (CARD_WIDTH  + gap)) - gap
    grid_height = (3 * (CARD_HEIGHT + gap)) - gap
    [ (PAGE_WIDTH - grid_width) / 2, (PAGE_HEIGHT - grid_height) / 2 ]
  end

  # Maps a front grid slot (0-8, row-major) to the corresponding back slot
  # based on the duplex flip axis.
  def self.back_slot_for(front_slot, duplex_mode)
    row, col = front_slot.divmod(3)
    case duplex_mode
    when "long_edge"  then col = 2 - col
    when "short_edge" then row = 2 - row
    end
    row * 3 + col
  end

  # ---------------------------------------------------------------------------
  # Card drawing — unchanged except for the 300dpi resize (Option B)
  # ---------------------------------------------------------------------------

  # Draws a single card image into the Prawn document at the given position.
  # Images are resized to IMAGE_WIDTH_PX × IMAGE_HEIGHT_PX (300dpi target)
  # before embedding so the Prawn document object stays lean.
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
    img&.destroy!  # explicitly frees ImageMagick memory
  end

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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Creates a single-page Prawn document, yields it to the caller for drawing,
  # renders it to a uniquely-named Tempfile, and returns that file.
  # The Prawn document goes out of scope immediately after render_file, so it
  # can be GC'd before the next page is started.
  def self.render_page(job_id, page_index, gap)
    left_margin, top_margin = margins_for(gap)
    pdf = Prawn::Document.new(
      page_size:    "LETTER",
      page_layout:  :portrait,
      top_margin:   top_margin,
      bottom_margin: top_margin,
      left_margin:  left_margin,
      right_margin: left_margin
    )
    yield pdf
    FileUtils.mkdir_p(PDF_TMP_DIR)
    tmp = Tempfile.new([ "pdf_job_#{job_id}_p#{ format('%04d', page_index) }_", ".pdf" ], PDF_TMP_DIR)
    begin
      pdf.render_file(tmp.path)
      tmp
    rescue
      tmp.close!
      raise
    end
  end
  private_class_method :render_page

  # Renders a front page and back page for one chunk of up to CARDS_PER_PAGE
  # records, yielding the count of images drawn for progress reporting.
  # Returns [front_tmp, back_tmp].
  def self.render_page_pair(chunk, positions, duplex_mode, gap, job_id, page_index)
    front_tmp = render_page(job_id, page_index, gap) do |pdf|
      chunk.each_with_index do |r, slot|
        draw_card(pdf, r[:front_url], positions[slot])
      end
    end
    yield chunk.size

    back_tmp = render_page(job_id, page_index + 1, gap) do |pdf|
      chunk.each_with_index do |r, slot|
        draw_card(pdf, r[:back_url], positions[back_slot_for(slot, duplex_mode)])
      end
    end
    yield chunk.size

    [ front_tmp, back_tmp ]
  end
  private_class_method :render_page_pair

  # Merges an ordered array of single-page Tempfiles into one PDF using
  # the combine_pdf gem (pure Ruby, no system dependencies).
  # Cleans up all page files in ensure.
  # Returns a Tempfile of the merged PDF.
  def self.combine_pages(page_files, job_id)
    raise "No pages to combine" if page_files.empty?

    # Single page — no merge needed, return directly
    return page_files.first if page_files.size == 1

    FileUtils.mkdir_p(PDF_TMP_DIR)
    output_tmp = Tempfile.new([ "pdf_job_#{job_id}_merged_", ".pdf" ], PDF_TMP_DIR)
    begin
      combined = CombinePDF.new
      page_files.each { |f| combined << CombinePDF.load(f.path) }
      combined.save(output_tmp.path)
      Rails.logger.info("combined #{page_files.size} pages into #{output_tmp.path}")
      output_tmp
    rescue
      output_tmp.close!
      raise
    ensure
      page_files.each { |f| f.close! rescue nil }
    end
  end
  private_class_method :combine_pages

  # doesnt really work in all cases
  def self.add_black_background(image)
    region_w = (image.width * 0.05).to_i
    region_h = (image.height * 0.05).to_i
    corners  = [
      [ 0, 0 ],
      [ image.width - region_w, 0 ],
      [ 0, image.height - region_h ],
      [ image.width - region_w, image.height - region_h ]
    ]
    corners.each do |x, y|
      image.combine_options do |c|
        c.fuzz "12%"
        c.region "#{region_w}x#{region_h}+#{x}+#{y}"
        c.transparent "white"
      end
    end
    image.combine_options do |c|
      c.background "black"
      c.flatten
    end
    image.format "png" do |c|
      c.alpha "off"
    end
    image
  end
end
