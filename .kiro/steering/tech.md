# Tech Stack

## Core

- **Ruby** 3.3.5
- **Rails** 8.0.x — trimmed: ActionMailer, ActionMailbox, ActionText,
  ActiveStorage, ActionCable, Sprockets, and ActiveRecord/DB frameworks are
  **not loaded** (see `config/application.rb`). There is no database.
- **Puma** web server, **Propshaft** asset pipeline, **importmap-rails** +
  **Turbo** + **Stimulus** on the frontend, **Bootstrap 5.3** for styling.

## Key gems

- **prawn** — PDF generation (one page per Prawn document, see pdf-pipeline.md)
- **hexapdf** — pure-Ruby PDF merging (no system binary dependency; lazy
  loading keeps merge memory low)
- **mini_magick** — image processing (needs ImageMagick installed)
- **httparty** — ArkhamDB API calls
- **aws-sdk-s3** (`require: false`, loaded lazily in jobs) — PDF storage
- **redis** — optional job-state backend
- **get_process_mem** — RSS memory logging during jobs
- **recaptcha**, **fastimage**, **whenever** (cron), **kamal**/**thruster**
- Dev/test only: rspec-rails, capybara, selenium, rubocop-rails-omakase,
  brakeman, bundler-audit, derailed_benchmarks, dotenv, web-console

## Infrastructure

- Hosted on **Render** (low-cost tier, ~512MB RAM). Ephemeral filesystem —
  `tmp/` is wiped on redeploy.
- Build command: `./render-build.sh` (bundle install + asset precompile).
  Render is a **native Ruby** service, not Docker — `apt-get` is unavailable
  at build time (runs unprivileged), so all dependencies must be gems or
  already present in Render's image. This is why PDF merging uses the
  `hexapdf` gem rather than the `pdfunite` binary.
- **PDF storage:** AWS S3, private objects served via presigned URLs
  (`AWS_REGION`, `AWS_BUCKET` env vars).
- **Job queue:** ActiveJob with the `:async` adapter — jobs run in-process on a
  thread pool inside Puma. There is no separate worker process (avoids a second
  paid Render service). This means job memory competes with web request memory.

## Common commands

```bash
# Auto-format code
rubocop -a

# Run tests
bundle exec rspec

# Memory diagnostics (dev)
bundle exec derailed bundle:mem      # boot-time memory by gem
bundle exec derailed exec perf:mem   # per-request retained objects

# Test the PDF job API locally
curl -X POST http://localhost:3000/pdf_jobs \
  -H "Content-Type: application/json" \
  -d '{"deck_id": 57317}'
curl http://localhost:3000/pdf_jobs/<id>
curl -L -O http://localhost:3000/pdf_jobs/<id>/download
```

## Conventions

- Prefer dedicated tools/gems over shelling out to system binaries — the app
  must run on Render's unprivileged native build with no `apt-get`.
- Memory is the scarcest resource. Any change touching the PDF pipeline, image
  handling, or job processing should be evaluated for peak memory. Prefer
  streaming to disk over holding data in memory. See pdf-pipeline.md.
- Long-running work (dev servers, watchers) is never launched from tooling —
  run it manually.
