require "rails_helper"

RSpec.describe "ArkhamDbHelper" do
  context "#get_cards_from_deck_id" do
    it "calls the deck API and always includes the investigator card" do
      ret = ArkhamDbHelper.get_cards_from_deck_id(48985)
      # 20 deck slots + 1 investigator card (always prepended)
      expect(ret.count).to eq(21)
      # The investigator is inserted first
      investigator_key, investigator_qty = ret.first
      expect(investigator_qty).to eq(1)
      # The deck slots follow and still contain the expected card
      expect(ret["01025"]).to eq(2)
    end
  end

  context "#get_card" do
    it "calls the single card API" do
      ret = ArkhamDbHelper.get_card("10019")
      expect(ret["imagesrc"]).to eq("/bundles/cards/10019.png")
    end

    it "returns nil with invalid card_id" do
      ret = ArkhamDbHelper.get_card("12345")
      expect(ret).to eq nil
    end
  end

  context "#get_card_image_url" do
    it "returns a valid image URL" do
      ret = ArkhamDbHelper.get_card_image_url("10019")
      expect(ret).to eq "https://arkhamdb.com/bundles/cards/10019.png"
    end

    it "returns URL with invalid card_id" do
      ret = ArkhamDbHelper.get_card_image_url("12345")
      expect(ret).to eq "https://arkhamdb.com/bundles/cards/12345.png"
    end
  end
  # it "calls the all cards API" do
  #   ret = ArkhamDbHelper.get_all_cards()
  #   # pp ret
  # end
end
