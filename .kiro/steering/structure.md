# Project Structure

Standard Rails 8 layout. Key directories and the files that matter most:

```
app/
  controllers/
    home_controller.rb          # renders the main page (tabs + forms)
    pdf_jobs_controller.rb       # create / show(status) / cancel / download
    card_controller.rb           # legacy direct-download endpoints (inline PDF)
    faq_controller.rb
  jobs/
    application_job.rb
    generate_pdf_base_job.rb     # shared job logic: progress, S3 upload,
                                 #   duplex record building, cache warm-up
    generate_pdf_from_deck_job.rb
    generate_pdf_from_card_list_job.rb
    generate_pdf_from_scenario_job.rb
    cleanup_local_json_job_files.rb  # cron-invoked stale job/file cleanup
    pdf_generation_cancelled.rb  # exception used for cooperative cancellation
  helpers/
    pdf_helper.rb                # THE core: page rendering + batched merge
    arkham_db_helper.rb          # ArkhamDB API + card metadata cache
    card_image_cache.rb          # on-disk image cache
    card_back_helper.rb          # local faction card-back asset lookup
    letter_page.rb, pdf_helper.rb, application_helper.rb
  models/
    pdf_job.rb                   # job state (Redis or file backed), no DB
  views/
    home/index.html.erb          # the whole SPA-ish UI + polling JS
    partials/_print_options.html.erb  # shared print-options form fragment
    partials/_modals.html.erb
  middleware/ (loaded from lib/)
lib/
  reject_probes_middleware.rb    # drops scanner probes (.php, wp-*) before router
config/
  application.rb                 # trimmed framework requires; save_data_mode
  puma.rb                        # workers/threads (memory-tuned)
  schedule.rb                    # whenever cron: cleanup + cache pruning
  environments/                  # production.rb, development.rb
*.json (repo root)               # bundled campaign/scenario encounter data
scenarios.json                   # index of campaigns -> per-campaign JSON files
render-build.sh                  # Render build command
tmp/
  pdf_work/                      # intermediate + final PDF temp files
  card_image_cache/              # cached ArkhamDB card images
  jobdata/                       # file-backed PdfJob records (file mode)
```

## Where things live (mental map)

- **Request/response + polling flow:** `pdf_jobs_controller.rb` +
  `views/home/index.html.erb` (the polling JS is inline there).
- **Job orchestration:** the four `generate_pdf_*_job.rb` files. Each subclass
  gathers cards its own way, then defers to shared logic in
  `generate_pdf_base_job.rb`.
- **PDF construction & memory management:** `pdf_helper.rb`. This is the most
  performance-sensitive file in the repo — see pdf-pipeline.md.
- **External data & caching:** `arkham_db_helper.rb` (API + metadata cache),
  `card_image_cache.rb` (image files on disk).
- **Job persistence:** `pdf_job.rb` — a hand-rolled model, not ActiveRecord.

## Job class inheritance

```
ApplicationJob
  └─ GeneratePdfBaseJob        # generate_pdf_bin, report_progress,
       │                       #   build_records_with_backs, upload_to_s3
       ├─ GeneratePdfFromDeckJob
       ├─ GeneratePdfFromCardListJob
       └─ GeneratePdfFromScenarioJob
```

Each subclass implements `get_cards_hash` (or overrides `generate_pdf_bin`) to
produce the card set, then reuses the base class for progress, cache warming,
and upload.
