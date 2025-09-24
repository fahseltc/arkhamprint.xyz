class CreatePdfJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :pdf_jobs do |t|
      t.string :status
      t.string :file_url
      t.string :job_jid
      t.text :error_message

      t.timestamps
    end
  end
end
