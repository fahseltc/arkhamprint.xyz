class CreatePdfDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :pdf_documents do |t|
      t.timestamps
    end
  end
end
