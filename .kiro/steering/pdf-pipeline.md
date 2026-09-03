# PDF Pipeline, Caching & Memory Strategy

This is the most important and most performance-sensitive subsystem in the app.
Everything here exists to generate potentially large PDFs while staying under
Render's ~512MB memory cap. Read this before changing `pdf_helper.rb`,
`arkham_db_helper.rb`, `card_image_cache.rb`, or the job classes.

## The core problem

Prawn holds an entire PDF document in memory until `render_file` is called.
MiniMagick/ImageMagick can spike 10-20MB per image. A large campaign PDF can be
200+ pages. Naively building one Prawn document for the whole job, or merging
all pages into one in-memory PDF object at once, exhausts the 512MB cap and the
container is killed and restarted. The pipeline below keeps peak memory flat
regardless of card count.

## Page-at-a-time generation (`PdfHelper`)

Layout facts: 9 cards per LETTER page in a 3×3 grid, each card drawn at exactly
2.5in × 3.5in (180 × 252 pt). Optional 2mm gap between cards (`DEFAULT_GAP`);
`gap: 0` packs edge-to-edge. Margins are derived from grid+gap so the grid
always fits.

- **`generate(cards, ...)`** — front-only. `cards` is `{ url => quantity }`.
- **`generate_with_backs(records, ...)`** — duplex. `records` is
  `[{ front_url:, back_url:, quantity: }]`. Each 9-card chunk emits a front
  page immediately followed by its back page.
- **`back_slot_for(slot, duplex_mode)`** — maps a front grid slot to its back
  slot. `none` = no mirroring, `long_edge` = mirror columns, `short_edge` =
  mirror rows, matching the printshop duplexer's physical flip axis.

Both entry points:
1. Iterate cards into chunks of `CARDS_PER_PAGE` (9) **without** materializing
   the full duplicated list (iterate quantities directly).
2. Render each page as its **own single-page Prawn document** via
   `render_page`, write it to a temp file in `tmp/pdf_work/`, and let the Prawn
   object go out of scope so it is GC'd before the next page. Only one page's
   worth of Prawn state is ever in memory.
3. Collect the per-page temp files and hand them to `combine_pages`.
4. `yield(current_card)` per drawn card so the job can report progress.

`draw_card` opens the image, rotates landscape images, center-crops to the card
ratio, draws it, and **always calls `img.destroy!` in an `ensure`** to free
ImageMagick memory immediately. Do not remove that `destroy!`.

> Note: an earlier optimization resized images to a 300dpi target before
> embedding, but it was reverted because it cropped some images incorrectly.
> Images are embedded at source resolution. If revisiting for memory, verify
> crop correctness across card types first.

## Batched hierarchical merge (`combine_pages`)

Merging uses **HexaPDF** (`HexaPDF::Document.open` + `target.import(page)` +
`target.write(optimize: true)`), whose lazy loading avoids holding every source
document fully in memory. The assembled document's object tree still lives in
memory before write, so we merge in bounded batches anyway:

- Pages are merged in batches of `MERGE_BATCH_SIZE` (currently 10) into
  intermediate temp files. After each batch the HexaPDF document is released
  and a full GC is forced (`reclaim_memory(0, force: true)`).
- Intermediates are then merged the same way, **recursively** (`merge_recursive`
  → `merge_batch`), until a single file remains.
- Peak memory is bounded to ~one batch of pages regardless of total page count.
- Source files are `close!`d as they are consumed; everything is cleaned up on
  error via `ensure`.

Tuning: lower `MERGE_BATCH_SIZE` = lower peak memory, more passes. If merge-time
memory logs (`Merged batch ... mem=`) creep toward the cap, lower it.

Merging uses the **`hexapdf` gem** (pure Ruby), NOT the `pdfunite` binary —
Render's native build can't `apt-get` system packages.

## Temp files

All intermediate and final PDFs go to `tmp/pdf_work/` (`PDF_TMP_DIR`), not the
OS `/tmp`, so they're easy to find and clean up. Names embed the job id.
Callers of `generate`/`generate_with_backs` receive a `Tempfile` and are
responsible for `close!`ing it — `store_pdf` does this in an `ensure`.

## Storage backend (`PdfStorage`)

Finished PDFs go through `PdfStorage`, which has two backends chosen at boot by
`config.pdf_storage_mode` (set in `config/application.rb`). The mode is `:s3`
when `AWS_BUCKET` is present, otherwise `:local`. Setting `FORCE_USE_LOCAL=true`
forces `:local` even when AWS is configured (for testing the local path):

- `:s3` (production) — uploads to S3, `file_url` is the S3 object key, served
  via a short-lived presigned URL.
- `:local` (dev without AWS) — writes to `tmp/pdf_output/`, `file_url` is a
  `local:<filename>` sentinel, served directly by the controller with
  `send_file`. Lets contributors run the full flow with no AWS setup.

`aws-sdk-s3` is required lazily inside `PdfStorage` only when the S3 backend is
actually used, so local dev never loads it.

### S3 cleanup (not in app code)

Generated PDFs in S3 are NOT deleted by the app. Cleanup is handled by an **S3
lifecycle rule** on the bucket (`expire-generated-pdfs`, prefix `uploads/pdf/`,
expire after 1 day), which S3 runs server-side daily. This is intentional — it
runs even when the Render instance is asleep and costs no app memory/CPU.
Download links are presigned with a 5-minute expiry, so PDFs never need to
persist long. If you go looking for S3 cleanup logic in Ruby, there isn't any —
it lives in the bucket's lifecycle configuration
(`aws s3api get-bucket-lifecycle-configuration --bucket <bucket>`).

## Two caches

### 1. Card image cache (`CardImageCache`) — on disk

- Caches ArkhamDB card images to `tmp/card_image_cache/`, keyed by URL basename.
- `fetch(url)` returns a local path, downloading on a miss. Local asset paths
  (faction card backs) bypass the cache.
- Writes to a `.tmp` sidecar then atomically renames, so concurrent threads
  never read a partial file.
- Falls back from `.png` to `.jpg` on HTTP 404.
- Stale entries (older than `MAX_AGE`, 30 days) are pruned by a daily cron
  (`config/schedule.rb`). Card art is effectively immutable.
- On Render the filesystem is ephemeral, so this warms per-deploy.

### 2. Card metadata cache (`ArkhamDbHelper::CARD_META_CACHE`) — in memory

- Process-level constant, mutex-guarded, never invalidated (card data is
  immutable). ~150-250 bytes/card; the whole card pool would be ~2-3MB. Each
  Puma worker has its own copy. This is negligible against PDF memory — do not
  add an LRU/eviction unless profiling shows it matters.
- `get_card_back_info(card_id)` returns `{ double_sided:, back_image_url:,
  faction_code: }`, fetching from the ArkhamDB card API on a miss.
- `resolve_back_url(card_id)` returns the real ArkhamDB back image if the card
  is double-sided, else the local faction card-back asset (`CardBackHelper`).
- `warm_card_meta_cache(card_ids)` pre-fetches many cards concurrently (bounded
  pool, 8 threads) since the calls are IO-bound. It yields `(done, total)` so
  jobs can drive the progress bar during warm-up instead of stalling. Threads
  are joined before it returns; transient memory is a few hundred KB.

## Job flow & progress

`GeneratePdfBaseJob` holds the shared logic:
- `build_records_with_backs` warms the metadata cache first (driving the first
  ~10% of the progress bar), then builds duplex records via `resolve_back_url`.
- `report_progress(idx)` writes `current_progress` and checks for cooperative
  cancellation (see below). It logs one line per page to keep logs readable.
- `store_pdf` persists the temp file via `PdfStorage` (S3 or local) and closes
  it in `ensure`.

### Cooperative cancellation

The Cancel button flips the stored job status. The running job notices on its
next `report_progress` and raises `PdfGenerationCancelled`. The status is
checked BEFORE writing progress, because `@pdf_job` is a stale in-memory
snapshot and `save!` writes the whole record — writing first would clobber a
freshly-set "cancelled" back to "pending".

## Investigator card special case

The investigator card is double-sided and its reverse is real content, not a
decorative back. It's always included. With backs OFF, the deck job explicitly
adds the investigator's back image as its own front-facing card
(`add_investigator_back_as_front`). Do not add a separate `#{code}b` entry when
building the card list — that would double-print the back in duplex mode.

## Rules of thumb when changing this subsystem

- Evaluate every change for **peak memory**, not just correctness. Log
  `mem=#{mem_mb}MB` around new hot spots (see `PdfHelper.mem_mb`).
- Prefer streaming to disk over accumulating in memory.
- Free ImageMagick objects (`destroy!`) and close temp files (`close!`)
  promptly, in `ensure` blocks.
- Never reintroduce a whole-document-in-memory merge or a single giant Prawn
  document.
- No new system-binary dependencies — gems only (Render native build).
