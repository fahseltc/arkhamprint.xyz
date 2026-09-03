# ArkhamPrint.XYZ
Hosted at https://arkhamprint.xyz/

This project helps players of the Arkham Horror LCG print proxy cards at home.
Card images are sourced from [arkhamdb.com](https://arkhamdb.com/) and laid out
9 per page (a 3×3 grid at true card size). Cards can be requested from a deck
URL, a list of card IDs, or a bundled campaign/scenario, with options for
duplex card backs, cutting gaps, and duplex mirroring modes.

## Technical Details
Uses Ruby 3.3.5 and Rails 8.0.x. Frontend uses Bootstrap 5.3.3 and jQuery 3.7.1
loaded via CDN, with importmap-rails + Turbo + Stimulus.
Hosted on [Render](https://render.com/) low-cost tier.
- This means there can be some initial startup time after the instance has been
  idle. It also imposes a ~512MB memory cap that shapes much of the design.

PDF generation runs as a background job (ActiveJob, `:async` adapter — jobs run
in-process, no separate worker). The browser submits a job, then polls for
status and progress. In production completed PDFs are stored in S3 and served
via a short-lived presigned URL. Large PDFs are built one page at a time and
merged in bounded batches to keep memory flat under the cap.

For a deeper architecture overview see the steering docs in `.kiro/steering/`.

## Local development setup

The app runs end to end with **no configuration and no AWS account**:

```
bundle install
cp .env.example .env   # optional — see below
bin/rails server
```

Without any AWS credentials, generated PDFs are written to `tmp/pdf_output/`
and served directly by the app instead of being uploaded to S3. This is
controlled automatically: if `AWS_BUCKET` is set in the environment the app
uses S3, otherwise it uses local file storage. So contributors can build and
download PDFs locally without any secrets. Copy `.env.example` to `.env` only
if you want to exercise the real S3 integration locally.

## Code formatting
run `rubocop -a` to auto-format the code.


# Test Curl commands

Create a job (returns a JSON body with `pdf_job_id`, a UUID):
```
curl -X POST http://localhost:3000/pdf_jobs \
  -H "Content-Type: application/json" \
  -d '{ "deck_id": 57317 }'
```

Poll status, then download using the returned id:
```
curl http://localhost:3000/pdf_jobs/<pdf_job_id>
curl -L -O http://localhost:3000/pdf_jobs/<pdf_job_id>/download
```