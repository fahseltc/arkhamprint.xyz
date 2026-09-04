require "rails_helper"

# Behavioural specs for the three GeneratePdfFrom* jobs, exercising the shared
# perform skeleton (find job -> parse -> generate -> store, with cancel/failure
# handling). All heavy collaborators are stubbed so these are fast and never
# touch the network, ImageMagick, S3, or the real PDF pipeline.
RSpec.describe "GeneratePdfFrom* jobs" do
  # A stand-in for the Tempfile that PdfHelper.generate* returns.
  let(:fake_pdf) { instance_double(Tempfile, path: "/tmp/fake.pdf", close!: nil) }

  before do
    # Neutralise the actual PDF construction and storage.
    allow(PdfHelper).to receive(:generate).and_return(fake_pdf)
    allow(PdfHelper).to receive(:generate_with_backs).and_return(fake_pdf)
    allow(PdfStorage).to receive(:store).and_return("local:test.pdf")
    # Metadata warm-up is a no-op in these specs.
    allow(ArkhamDbHelper).to receive(:warm_card_meta_cache)
    allow(ArkhamDbHelper).to receive(:resolve_back_url).and_return("back.png")
  end

  # Runs the job inline and returns the reloaded PdfJob record.
  def run(job_class, params)
    pdf_job = PdfJob.create!(status: "pending")
    job_class.new.perform(pdf_job.id, params)
    PdfJob.find(pdf_job.id)
  end

  # Runs the job expecting it to re-raise (failure path).
  def run_expecting_raise(job_class, params)
    pdf_job = PdfJob.create!(status: "pending")
    expect { job_class.new.perform(pdf_job.id, params) }.to raise_error(StandardError)
    PdfJob.find(pdf_job.id)
  end

  # --- GeneratePdfFromDeckJob ----------------------------------------------
  describe GeneratePdfFromDeckJob do
    let(:params) { { "deck_id" => "48985", "print_backs" => false } }

    before do
      allow(ArkhamDbHelper).to receive(:fetch_deck).with("48985").and_return(
        cards: { "60101" => 1, "01025" => 2 }, investigator_code: "60101"
      )
      allow(ArkhamDbHelper).to receive(:bonded_cards_for).and_return({})
      allow(ArkhamDbHelper).to receive(:get_card_back_info).with("60101").and_return(
        double_sided: false, back_image_url: nil, faction_code: "guardian"
      )
    end

    it "completes and records the stored file_url on success" do
      job = run(described_class, params)
      expect(job.status).to eq("completed")
      expect(job.file_url).to eq("local:test.pdf")
    end

    it "marks the job cancelled when generation is cancelled" do
      allow(PdfHelper).to receive(:generate).and_raise(PdfGenerationCancelled)
      job = run(described_class, params)
      expect(job.status).to eq("cancelled")
    end

    it "marks the job failed and re-raises on an unexpected error" do
      allow(PdfHelper).to receive(:generate).and_raise(StandardError, "boom")
      job = run_expecting_raise(described_class, params)
      expect(job.status).to eq("failed")
      expect(job.error_message).to eq("boom")
    end

    it "raises (and fails) when deck_id is missing" do
      job = run_expecting_raise(described_class, {})
      expect(job.status).to eq("failed")
    end
  end

  # --- GeneratePdfFromCardListJob ------------------------------------------
  describe GeneratePdfFromCardListJob do
    let(:params) { { "card_ids" => %w[01025 01026], "print_backs" => false } }

    it "completes on success" do
      job = run(described_class, params)
      expect(job.status).to eq("completed")
      expect(job.file_url).to eq("local:test.pdf")
    end

    it "marks the job cancelled when generation is cancelled" do
      allow(PdfHelper).to receive(:generate).and_raise(PdfGenerationCancelled)
      job = run(described_class, params)
      expect(job.status).to eq("cancelled")
    end

    it "marks the job failed and re-raises on an unexpected error" do
      allow(PdfHelper).to receive(:generate).and_raise(StandardError, "boom")
      job = run_expecting_raise(described_class, params)
      expect(job.status).to eq("failed")
    end

    it "raises (and fails) when card_ids is missing" do
      job = run_expecting_raise(described_class, {})
      expect(job.status).to eq("failed")
    end

    it "uses the duplex pipeline when print_backs is true" do
      expect(PdfHelper).to receive(:generate_with_backs).and_return(fake_pdf)
      job = run(described_class, params.merge("print_backs" => true))
      expect(job.status).to eq("completed")
    end
  end

  # --- GeneratePdfFromScenarioJob ------------------------------------------
  describe GeneratePdfFromScenarioJob do
    let(:params) do
      { "scenario_title" => "The Gathering", "campaign_file" => "03_night.json", "print_backs" => false }
    end

    let(:scenario_cards) do
      [ { "id" => "01118", "quantity" => 1, "has_back" => false, "faction_code" => "mythos" } ]
    end

    before do
      allow(ArkhamDbHelper).to receive(:scenarios_index).and_return(
        "campaigns" => [ { "file" => "03_night.json", "name" => "Night of the Zealot" } ]
      )
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(Rails.root.join("03_night.json")).and_return(
        { "missions" => { "The Gathering" => { "scenario_cards" => scenario_cards } } }.to_json
      )
      allow(CardBackHelper).to receive(:path_for).and_return("mythos.jpg")
    end

    it "completes on success" do
      job = run(described_class, params)
      expect(job.status).to eq("completed")
      expect(job.file_url).to eq("local:test.pdf")
    end

    it "fails when the campaign is not found" do
      allow(ArkhamDbHelper).to receive(:scenarios_index).and_return("campaigns" => [])
      job = run_expecting_raise(described_class, params)
      expect(job.status).to eq("failed")
    end

    it "fails when the scenario is not found" do
      job = run_expecting_raise(described_class, params.merge("scenario_title" => "Nope"))
      expect(job.status).to eq("failed")
    end

    it "marks the job cancelled when generation is cancelled" do
      allow(PdfHelper).to receive(:generate).and_raise(PdfGenerationCancelled)
      job = run(described_class, params)
      expect(job.status).to eq("cancelled")
    end
  end
end
