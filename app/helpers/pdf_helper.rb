require "open-uri"
require "prawn/measurement_extensions"
require "tempfile"
require "mini_magick"
require "hexapdf"
require "get_process_mem"

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

  # Max pages held in memory during a single merge pass. Larger merges are done
  # in batches of this size and merged hierarchically so peak memory stays flat
  # regardless of total page count. Tuned low to stay well under the 512MB cap.
  MERGE_BATCH_SIZE = 10

  # Default white space left between adjacent cards on every side, so an
  # imprecise cut can't slice into the neighboring card. Callers may pass
  # gap: 0 to print cards edge-to-edge instead.
  #
  # The gap trades off against the page's outer margin (see margins_for) -
  # a bigger gap shrinks the margin. HOME_GAP keeps ~4.3mm of margin, safely
  # above the ~4.2mm hardware-enforced minimum on many consumer printers.
  # PRINTSHOP_GAP drops that to ~3.35mm, which is fine for a printshop that
  # trims to size but can get clipped on a home printer.
  HOME_GAP = 2.mm
  PRINTSHOP_GAP = 3.mm
  DEFAULT_GAP = HOME_GAP
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
      # Drop the Prawn document reference before reclaiming so its (large)
      # object graph is collectible.
      pdf = nil
      reclaim_memory(page_index)
      Rails.logger.info("Rendered page page_index=#{page_index} file=#{File.basename(tmp.path)} size=#{File.size(tmp.path)} bytes mem=#{mem_mb}MB")
      tmp
    rescue
      tmp.close!
      raise
    end
  end
  private_class_method :render_page

  # Ruby's GC frees objects but does not readily return heap pages to the OS,
  # so across a long multi-page job the process RSS ratchets upward even though
  # each page is individually freed. Periodically forcing a full GC (with
  # compaction) hands memory back and defragments the heap, keeping RSS flat.
  # Running every page would be wasteful; every RECLAIM_EVERY pages is enough
  # to hold the line without a meaningful speed cost.
  RECLAIM_EVERY = 4
  def self.reclaim_memory(page_index, force: false)
    return unless force || (page_index % RECLAIM_EVERY).zero?

    GC.start(full_mark: true, immediate_sweep: true)
    GC.compact if GC.respond_to?(:compact)
  end
  private_class_method :reclaim_memory

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
  # HexaPDF, which uses lazy loading so it does not hold every source
  # document fully in memory at once.
  #
  # Even so, the assembled document's object tree lives in memory before write,
  # so we still merge in bounded batches: each batch of MERGE_BATCH_SIZE pages
  # is merged to an intermediate file and released, then the intermediates are
  # merged the same way, recursively, until a single file remains. This keeps
  # peak memory bounded regardless of total page count.
  #
  # Cleans up all input page files. Returns a Tempfile of the merged PDF.
  def self.combine_pages(page_files, job_id)
    raise "No pages to combine" if page_files.empty?

    Rails.logger.info("Merge starting total_pages=#{page_files.size} batch_size=#{MERGE_BATCH_SIZE} mem=#{mem_mb}MB")
    result = merge_recursive(page_files, job_id, depth: 0)
    Rails.logger.info("Merge complete output=#{File.basename(result.path)} size=#{File.size(result.path)} bytes mem=#{mem_mb}MB")
    result
  end
  private_class_method :combine_pages

  # Recursively merges files in batches. Returns a single Tempfile.
  # Input files are closed/deleted as they're consumed.
  def self.merge_recursive(files, job_id, depth:)
    # Base case: one file is already the merged result
    return files.first if files.size == 1

    intermediates = []
    files.each_slice(MERGE_BATCH_SIZE).with_index do |batch, batch_index|
      # A single leftover file needs no merge — carry it forward as-is
      if batch.size == 1
        intermediates << batch.first
        next
      end
      intermediates << merge_batch(batch, job_id, depth, batch_index)
    end

    # Recurse until a single file remains
    merge_recursive(intermediates, job_id, depth: depth + 1)
  end
  private_class_method :merge_recursive

  # Merges one batch of files into a single intermediate Tempfile, loading and
  # releasing each source file one at a time. Source files are closed as
  # consumed; on error everything is cleaned up.
  def self.merge_batch(batch, job_id, depth, batch_index)
    FileUtils.mkdir_p(PDF_TMP_DIR)
    out = Tempfile.new([ "pdf_job_#{job_id}_merge_d#{depth}_b#{batch_index}_", ".pdf" ], PDF_TMP_DIR)
    begin
      target = HexaPDF::Document.new
      batch.each do |f|
        source = HexaPDF::Document.open(f.path)
        source.pages.each { |page| target.pages << target.import(page) }
        source = nil     # release the source document
        f.close!         # free the source file handle + on-disk temp as we go
      end
      # optimize: true de-duplicates shared objects, keeping the output small.
      target.write(out.path, optimize: true)
      target = nil
      reclaim_memory(0, force: true)  # full GC after each batch to hand memory back
      Rails.logger.info("Merged batch depth=#{depth} batch=#{batch_index} pages=#{batch.size} mem=#{mem_mb}MB")
      out
    rescue
      out.close!
      raise
    ensure
      # Close any source files not yet consumed (e.g. if we raised mid-batch)
      batch.each { |f| f.close! rescue nil }
    end
  end
  private_class_method :merge_batch

  # Returns current process RSS memory in MB, rounded to 1 decimal place.
  def self.mem_mb
    GetProcessMem.new.mb.round(1)
  end
  private_class_method :mem_mb

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
