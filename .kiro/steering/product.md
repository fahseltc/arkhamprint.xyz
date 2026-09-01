# Product Overview

ArkhamPrint.XYZ (hosted at https://arkhamprint.xyz/) is a web app that helps
players of the Arkham Horror: The Card Game print proxy cards at home.

## What it does

Users generate print-ready PDFs of cards laid out 9-per-page (a 3×3 grid at
true card size, 2.5in × 3.5in). Card images come from
[ArkhamDB](https://arkhamdb.com/). There are three ways to request a PDF, each
exposed as a tab in the UI:

1. **From Deck URL** — paste an ArkhamDB deck URL or deck ID. The full deck
   (plus the investigator card) is printed.
2. **From Card List** — paste a comma/space separated list of ArkhamDB card
   IDs (e.g. `01022, 01044`).
3. **Campaigns** — pick a single scenario from a bundled index of
   encounter-card data (`scenarios.json` + per-campaign JSON files). There is
   deliberately no "whole campaign at once" option — it produced PDFs large
   enough to threaten the 512MB memory cap.

## Print options (shared across all three tabs)

- **Print card backs** — produces a duplex front/back layout so a printshop can
  print both sides. When off, only fronts print (except the investigator card,
  whose reverse is real content and always prints).
- **Card spacing** — a 2mm gap between cards so cutting can't slice into a
  neighbor. Can be turned off for edge-to-edge printing.
- **Duplex mode** — `none`, `long_edge`, or `short_edge`, controlling how the
  back-page grid is mirrored to match the printshop's duplexer flip axis.

## Job model

PDF generation runs as a background job (ActiveJob, async adapter). The browser
submits a job, receives a job id, then polls for status and a progress bar.
Completed PDFs are uploaded to S3 and served to the user via a short-lived
presigned URL. Jobs can be cancelled cooperatively mid-run.

## Constraints that shape the design

- Hosted on Render's low-cost tier with a **512MB memory cap**. Staying under
  this cap is a primary, ongoing design constraint — see `pdf-pipeline.md`.
- No traditional database. Job state is stored in Redis or local JSON files
  (see `PdfJob`), selected by `config.save_data_mode`.
