class PdfDocument < ApplicationRecord
  mount_uploader :file, PdfUploader
end
