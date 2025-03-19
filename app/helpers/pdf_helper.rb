require "open-uri"
require "prawn/measurement_extensions"

# Prawn PDF origin location is at the bottom-left corner of the page (0,0)
# page still filled from top to bottom using the cursor - starts at the top
# The base unit in Prawn is the PDF Point. One PDF Point is equal to 1/72 of an inch.
# 1 inch in PDF Points: 72 pt
# 2.5 x 3.5 for standard card sizes so 180 pts x 252
# LETTER Page size 612.00 x 792.00   https://www.rubydoc.info/github/sandal/prawn/master/Prawn/Document/PageGeometry

module PdfHelper
  @x_cursor_position = 0
  @y_cursor_position = 756

  def self.generate(cards, page_size)
    pdf = Prawn::Document.new(
      page_size: "LETTER",
      page_layout: :portrait,
      top_margin: 18,
      bottom_margin: 18,
      left_margin: 36,
      right_margin: 36
    )
    @x_cursor_position = 0 # reset cursor
    @y_cursor_position = 756
    cards.each do |card_image_url, quantity|
      begin
        img = URI.open(card_image_url)
      rescue OpenURI::HTTPError
        next
      end
      quantity.times do
        Rails.logger.info("y position: " + @x_cursor_position.to_s)
        Rails.logger.info("x position: " + @y_cursor_position.to_s)
        add_image(pdf, img)
      end
    end
    Rails.logger.info("generating!")
    pdf.render
  end

  def self.add_image(pdf, img)
    pdf.image img, width: 2.5.send(:in), height: 3.5.send(:in), at: [ @x_cursor_position, @y_cursor_position ]
    if (@x_cursor_position += 180) >= 540
      @x_cursor_position = 0.0
      if (@y_cursor_position -= 252) < 100
        @y_cursor_position = 756.0
        pdf.start_new_page
      end
    end
  end
end


# 612.00 x 792.00

# cards are 180 pts x 252

# 540 total card width means 36 margin wide
# 756 total height means 18 margin top/bottom
