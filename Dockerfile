# syntax=docker/dockerfile:1
FROM ruby:3.3.5-slim

# System dependencies:
#   build-essential  — native gem compilation (e.g. nio4r)
#   imagemagick      — MiniMagick backend for card image processing
#   poppler-utils    — provides pdfunite for merging per-page PDFs
#   curl             — needed by some gem installs
#   git              — needed by bundler for git-sourced gems
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      curl \
      git \
      imagemagick \
      poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rails

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Copy application code
COPY . .

# Precompile assets
RUN bundle exec rake assets:precompile

# Create tmp directories used at runtime
RUN mkdir -p tmp/pdf_work tmp/card_image_cache tmp/jobdata

# Start Puma
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
