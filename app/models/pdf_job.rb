class PdfJob < ApplicationRecord
  validates :status, presence: true
end
