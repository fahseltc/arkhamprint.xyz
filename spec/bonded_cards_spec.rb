require "rails_helper"

# Tests ArkhamDbHelper's bonded-card resolution, which reads the static
# config/bonded_cards.json index (no network). Bonded cards (Dream-Eaters
# mechanic) are set aside with a deck and never listed by ArkhamDB's deck API,
# so we add them ourselves from the parent card present in the deck.
RSpec.describe "ArkhamDbHelper bonded cards" do
  describe ".bonded_cards_for" do
    it "returns the bonded card and quantity for a parent in the deck" do
      # 05313 = Hallowed Mirror -> 05314 Soothing Melody x3
      result = ArkhamDbHelper.bonded_cards_for([ "05313" ])
      expect(result).to eq("05314" => 3)
    end

    it "resolves multiple parents in one deck" do
      # 05313 -> 05314 x3 (Soothing Melody), 05316 -> 05317 x3 (Blood-Rite)
      result = ArkhamDbHelper.bonded_cards_for(%w[05313 05316])
      expect(result).to eq("05314" => 3, "05317" => 3)
    end

    it "returns an empty hash for a deck with no bonded parents" do
      expect(ArkhamDbHelper.bonded_cards_for(%w[01025 60101])).to eq({})
    end

    it "ignores unknown / non-parent ids" do
      expect(ArkhamDbHelper.bonded_cards_for([ "99999" ])).to eq({})
    end

    it "does not add bonded cards for a bonded card id itself (only its parent)" do
      # 05314 is the bonded card, not a parent — it shouldn't resolve anything.
      expect(ArkhamDbHelper.bonded_cards_for([ "05314" ])).to eq({})
    end
  end

  describe ".bonded_index" do
    it "loads the static index keyed by parent code" do
      index = ArkhamDbHelper.bonded_index
      expect(index).to be_a(Hash)
      # Each parent maps to an array of bonded-card entries.
      expect(index["05313"]).to include(
        a_hash_including("code" => "05314", "quantity" => 3)
      )
    end
  end
end
