#!/usr/bin/env bash
set -e

# Install poppler-utils for pdfunite (used during PDF generation to merge
# per-page PDF files into a single output without holding the whole document
# in memory at once).
apt-get install -y --no-install-recommends poppler-utils

bundle install
bundle exec rake assets:clean
bundle exec rake assets:precompile
