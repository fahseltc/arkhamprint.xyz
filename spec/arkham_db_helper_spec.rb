require "rails_helper"

RSpec.describe "ArkhamDbHelper" do
  # A realistic decklist response for deck 48985: investigator 60101, plus 20
  # real card slots and the 01000 random-basic-weakness placeholder (which
  # fetch_deck rejects). 01025 is present at quantity 2 (asserted below).
  let(:deck_slots) do
    slots = { "01000" => 1, "01025" => 2 }
    # pad out to 20 real slots so the count assertion is meaningful
    (1..19).each { |n| slots[format("600%02d", n)] = 1 }
    slots
  end

  let(:deck_body) do
    { "investigator_code" => "60101", "slots" => deck_slots }.to_json
  end

  context "#get_cards_from_deck_id" do
    before do
      stub_request(:get, "https://arkhamdb.com/api/public/decklist/48985")
        .to_return(status: 200, body: deck_body, headers: { "Content-Type" => "application/json" })
    end

    it "calls the deck API and always includes the investigator card" do
      ret = ArkhamDbHelper.get_cards_from_deck_id(48985)
      # 20 real deck slots (01000 rejected) + 1 investigator card (prepended)
      expect(ret.count).to eq(21)
      # The investigator is inserted first
      _investigator_key, investigator_qty = ret.first
      expect(investigator_qty).to eq(1)
      # The deck slots follow and still contain the expected card
      expect(ret["01025"]).to eq(2)
      # The random-basic-weakness placeholder is dropped
      expect(ret).not_to have_key("01000")
    end
  end

  context "#get_card" do
    it "calls the single card API" do
      stub_request(:get, "https://arkhamdb.com/api/public/card/10019")
        .to_return(
          status: 200,
          body: { "imagesrc" => "/bundles/cards/10019.png" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      ret = ArkhamDbHelper.get_card("10019")
      expect(ret["imagesrc"]).to eq("/bundles/cards/10019.png")
    end

    it "returns nil with invalid card_id" do
      # ArkhamDB responds 500 for unknown card ids.
      stub_request(:get, "https://arkhamdb.com/api/public/card/12345")
        .to_return(status: 500, body: "")

      expect(ArkhamDbHelper.get_card("12345")).to be_nil
    end
  end

  context "#get_card_image_url" do
    it "returns a valid image URL" do
      expect(ArkhamDbHelper.get_card_image_url("10019"))
        .to eq("https://arkhamdb.com/bundles/cards/10019.png")
    end

    it "returns URL with invalid card_id" do
      expect(ArkhamDbHelper.get_card_image_url("12345"))
        .to eq("https://arkhamdb.com/bundles/cards/12345.png")
    end
  end
end
