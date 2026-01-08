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
  def self.generate(cards, page_size)
    pdf = Prawn::Document.new(page_size: "LETTER", page_layout: :portrait,
                              top_margin: 18, bottom_margin: 18,
                              left_margin: 36, right_margin: 36)

    x_cursor = 0
    y_cursor = 756
    cards_count = cards.sum { |_, q| q }
    current_card = 1

    Rails.logger.info("generating PDF with cards count #{cards_count}")

    cards.each do |url, quantity|
      begin
        img = MiniMagick::Image.open(url)
      rescue OpenURI::HTTPError => e
        begin
          # Try again with JPG
          img = MiniMagick::Image.open(url.gsub(".png", ".jpg"))
        rescue OpenURI::HTTPError => e
          Rails.logger.warn("Failed to open #{url}: #{e.message} with either PNG or JPG")
          next
        end
      end

      quantity.times do
        Rails.logger.info("Printing card #{current_card}/#{cards_count} at (#{x_cursor}, #{y_cursor}) page #{pdf.page_number}")
        # Rotate if needed
        img.rotate(90) if img.width > img.height
        # img = PdfHelper.add_black_background(img)
        Tempfile.create([ "card", ".png" ]) do |f|
          img.write(f.path)
          pdf.image f.path, width: 2.5.in, height: 3.5.in, at: [ x_cursor, y_cursor ]
        end

        x_cursor += 180
        if x_cursor >= 540
          x_cursor = 0
          y_cursor -= 252
          if y_cursor < 100
            y_cursor = 756
            if current_card != cards_count
              pdf.start_new_page
            end
          end
        end
        yield(current_card)
        current_card += 1
      end
    end

    pdf.render
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




# 612.00 x 792.00

# cards are 180 pts x 252

# 540 total card width means 36 margin wide
# 756 total height means 18 margin top/bottom
