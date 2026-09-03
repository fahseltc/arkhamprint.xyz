class GeneratePdfBaseJob < ApplicationJob
  def generate_pdf_bin
    cards_hash = get_cards_hash
    @pdf_job.update!(max_progress: cards_hash.values.sum)
    Rails.logger.info("Starting PDF job=#{@pdf_job.short_id} type=#{self.class.name} cards=#{@pdf_job.max_progress} duplex=false")
    pdf_tmp = PdfHelper.generate(cards_hash, "LETTER", job_id: @pdf_job.id) do |idx|
      report_progress(idx)
    end
    pdf_tmp
  end

  # Cooperative cancellation: the "Cancel" button (see pdf_jobs_controller's
  # cancel action) just flips the job's stored status, so the running job has
  # to notice it itself - checked on every drawn image, same cadence as the
  # progress update it rides along with. Checked BEFORE updating progress:
  # `@pdf_job` is a stale in-memory snapshot (its `status` is whatever it was
  # when the job started), and `update!`/`save!` writes the whole record, so
  # updating first would overwrite a fresh "cancelled" back to "pending".
  def report_progress(idx)
    raise PdfGenerationCancelled if PdfJob.find(@pdf_job.id).status == "cancelled"
    @pdf_job.update!(current_progress: idx)
    # Log one progress line per page (every 9 cards) to keep logs readable
    if idx % PdfHelper::CARDS_PER_PAGE == 0 || idx == @pdf_job.max_progress
      Rails.logger.info("Progress job=#{@pdf_job.short_id} #{idx}/#{@pdf_job.max_progress} cards (#{(idx.to_f / @pdf_job.max_progress * 100).round}%)")
    end
  end

  # Builds the [{ front_url:, back_url:, quantity: }] records array for a duplex
  # job. Warms the card metadata cache concurrently first, driving the progress
  # bar during the fetch phase so the UI isn't stuck "initializing" while all
  # the ArkhamDB lookups happen. Progress during warm-up is scaled against the
  # final total_images so the bar advances smoothly into the drawing phase.
  #
  # cards_hash is { front_image_url => quantity }.
  def build_records_with_backs(cards_hash, total_images)
    card_ids = cards_hash.keys.map { |url| File.basename(url, ".*") }

    # Reserve the first ~10% of the progress bar for the metadata warm-up so
    # the user sees immediate movement, then drawing fills the remaining 90%.
    warmup_span = [ (total_images * 0.1).ceil, 1 ].max
    @pdf_job.update!(max_progress: total_images, current_progress: 0)

    ArkhamDbHelper.warm_card_meta_cache(card_ids) do |done, total|
      scaled = (done.to_f / total * warmup_span).floor
      @pdf_job.update!(current_progress: scaled)
    end

    cards_hash.map do |front_url, quantity|
      card_id  = File.basename(front_url, ".*")
      back_url = ArkhamDbHelper.resolve_back_url(card_id)
      Rails.logger.debug("Card #{card_id} back_url=#{back_url}")
      { front_url: front_url, back_url: back_url, quantity: quantity }
    end
  end

  # Persists the finished PDF via PdfStorage (S3 in production, local disk in
  # dev without AWS) and marks the job completed. Returns the stored file_url.
  def store_pdf(pdf_tmp)
    file_url = PdfStorage.store(@pdf_job.id, pdf_tmp.path)

    Rails.logger.info("Stored job=#{@pdf_job.short_id} mode=#{PdfStorage.mode} file_url=#{file_url}")
    @pdf_job.update!(
      status: "completed",
      file_url: file_url,
      current_progress: @pdf_job.max_progress
    )
    file_url
  ensure
    pdf_tmp&.close!
  end

  def get_cards_hash
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end

  private

  # Coerces a checkbox-style param to a boolean. The frontend sends a real JSON
  # boolean, but depending on parameter parsing it can arrive as the boolean
  # `false` OR the string "false"/"0" — so a bare `param != false` check is
  # unreliable. Treats false, "false", "0", "" and nil as false; everything
  # else (including true and "true") as true. `default` is used when the param
  # is absent entirely.
  def param_flag(value, default: true)
    return default if value.nil?

    !%w[false 0].include?(value.to_s.strip.downcase) && value != false
  end
end
