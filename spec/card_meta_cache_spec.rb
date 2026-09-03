require "rails_helper"

# Tests the in-process card metadata cache in ArkhamDbHelper
# (get_card_back_info / resolve_back_url), which avoids re-hitting the ArkhamDB
# card API for cards already seen this process.
RSpec.describe "ArkhamDbHelper card metadata cache" do
  let(:card_id) { "01001" }

  # The cache is a process-level constant; clear the key under test so each
  # example deterministically exercises the miss-then-hit path.
  before { ArkhamDbHelper::CARD_META_CACHE.delete(card_id) }
  after  { ArkhamDbHelper::CARD_META_CACHE.delete(card_id) }

  describe ".get_card_back_info" do
    it "fetches once on a miss and returns normalized back info" do
      fake = {
        "double_sided" => true,
        "backimagesrc" => "/bundles/cards/01001b.png",
        "faction_code" => "guardian"
      }
      expect(ArkhamDbHelper).to receive(:get_card).with(card_id).once.and_return(fake)

      info = ArkhamDbHelper.get_card_back_info(card_id)

      expect(info[:double_sided]).to be true
      expect(info[:back_image_url]).to eq("https://arkhamdb.com/bundles/cards/01001b.png")
      expect(info[:faction_code]).to eq("guardian")
    end

    it "does not re-fetch on a second lookup (cache hit)" do
      fake = { "double_sided" => false, "backimagesrc" => nil, "faction_code" => "neutral" }
      # get_card must be called exactly once across both lookups.
      expect(ArkhamDbHelper).to receive(:get_card).with(card_id).once.and_return(fake)

      first  = ArkhamDbHelper.get_card_back_info(card_id)
      second = ArkhamDbHelper.get_card_back_info(card_id)

      expect(second).to eq(first)
    end

    it "stores a safe fallback when the API returns nothing" do
      expect(ArkhamDbHelper).to receive(:get_card).with(card_id).once.and_return(nil)

      info = ArkhamDbHelper.get_card_back_info(card_id)

      expect(info[:double_sided]).to be false
      expect(info[:back_image_url]).to be_nil
      # The fallback is cached too, so a broken endpoint isn't hammered.
      expect(ArkhamDbHelper::CARD_META_CACHE).to have_key(card_id)
    end
  end

  describe ".resolve_back_url" do
    it "returns the ArkhamDB back image for a double-sided card" do
      allow(ArkhamDbHelper).to receive(:get_card).with(card_id).and_return(
        "double_sided" => true,
        "backimagesrc" => "/bundles/cards/01001b.png",
        "faction_code" => "guardian"
      )
      expect(ArkhamDbHelper.resolve_back_url(card_id))
        .to eq("https://arkhamdb.com/bundles/cards/01001b.png")
    end

    it "falls back to the local faction card back for a single-sided card" do
      allow(ArkhamDbHelper).to receive(:get_card).with(card_id).and_return(
        "double_sided" => false,
        "backimagesrc" => nil,
        "faction_code" => "mythos"
      )
      expect(ArkhamDbHelper.resolve_back_url(card_id))
        .to eq(CardBackHelper.path_for("mythos"))
    end
  end
end
