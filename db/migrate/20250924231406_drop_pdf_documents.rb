class DropPdfDocuments < ActiveRecord::Migration[8.0]
  def change
    drop_table :pdf_documents
  end
end
