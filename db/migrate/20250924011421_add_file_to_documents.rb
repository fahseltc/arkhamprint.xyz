class AddFileToDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :pdf_documents, :file, :string
  end
end
