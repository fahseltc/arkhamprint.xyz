class LetterPage
  include Prawn::View

  # 540 total card width area
  # 756 total card height area

  def initialize
    @x_cursor_position = 0
    @y_cursor_position = 756
  end

  def document
    @document ||= Prawn::Document.new(
      page_size: "LETTER",
      page_layout: :portrait,
      top_margin: 18,
      bottom_margin: 18,
      left_margin: 36,
      right_margin: 36
    )
  end

  def generate(cards)
    cards.each do |card_image_url, quantity|
      begin
        image = URI.open(card_image_url)
      rescue OpenURI::HTTPError
        next
      end
      quantity.times do
        #Rails.logger.info("y position: " + @y_position.to_s)
        #Rails.logger.info("x position: " + @x_position.to_s)
        add_image(image)
      end
    end
    render
  end

  def add_image(img)
    #add_square() # This does work but source images have white rounded corners built-in
    # fill_color '000000'
    # fill_rectangle [@x_cursor_position, @y_cursor_position], 180, 252
    # blend_mode(:Normal) do
      image img, width: 2.5.send(:in), height: 3.5.send(:in), at:[@x_cursor_position, @y_cursor_position]
      if ((@x_cursor_position += 180) >= 540)
        @x_cursor_position = 0.0
        if ((@y_cursor_position -= 252) < 100)
          @y_cursor_position = 756.0
          pdf.start_new_page
        end
      end
    #end
  end

  # def add_square
  #   fill_color '000000'
  #   fill_rectangle [@x_cursor_position, @y_cursor_position], 180, 252
  # end
end