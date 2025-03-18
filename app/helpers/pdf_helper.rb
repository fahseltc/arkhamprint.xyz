require 'open-uri'
require "prawn/measurement_extensions"

# Prawn PDF origin location is at the bottom-left corner of the page (0,0)
# page still filled from top to bottom using the cursor - starts at the top
# The base unit in Prawn is the PDF Point. One PDF Point is equal to 1/72 of an inch.
# 1 inch in PDF Points: 72 pt
# 2.5 x 3.5 for standard card sizes so 180 pts x 252
# LETTER Page size 612.00 x 792.00   https://www.rubydoc.info/github/sandal/prawn/master/Prawn/Document/PageGeometry

module PdfHelper
  @@x_position = 0
  @@y_position = 0

  def self.generate(cards, page_size)
    pdf = LetterPage.new()
    pdf.build_pdf(cards)
    pdf.render
  end
end


# 612.00 x 792.00

# cards are 180 pts x 252

# 540 total card width means 36 margin wide
# 756 total height means 18 margin top/bottom



