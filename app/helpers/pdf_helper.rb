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
    cards_count = cards.sum { |h| h[1] }
    current_card = 1
    cards.each do |card_image_url, quantity|
      begin
        img = MiniMagick::Image.open(card_image_url)
      rescue OpenURI::HTTPError
        next
      end
      quantity.times do
        Rails.logger.info("Printing card (#{current_card} out of #{cards_count}) at (#{@x_cursor_position}, #{@y_cursor_position}) on page: #{pdf.page_number}")
        add_image(pdf, img)
        current_card += 1
      end
    end
    pdf.render
  end

  def self.add_image(pdf, img)
    if img.width > img.height
      img.rotate(90)
    end
    # mask convert https://arkhamdb.com/bundles/cards/60115.png /home/charles/prog/mask.png -compose Multiply -composite output.png

    pdf.image img.format("png").path, width: 2.5.send(:in), height: 3.5.send(:in), at: [ @x_cursor_position, @y_cursor_position ]
    if (@x_cursor_position += 180) >= 540
      @x_cursor_position = 0.0
      if (@y_cursor_position -= 252) < 100
        @y_cursor_position = 756.0
        pdf.start_new_page
      end
    end
    img.destroy!
  end
end


# 612.00 x 792.00

# cards are 180 pts x 252

# 540 total card width means 36 margin wide
# 756 total height means 18 margin top/bottom
