require "rails_helper"

RSpec.describe "ArkhamDbHelper" do
  context "#get_cards_from_deck_id" do
    it "calls the deck API" do
      ret = ArkhamDbHelper.get_cards_from_deck_id(48985)
      expect(ret.count).to eq(20)
      key, value = ret.first
      expect(key).to eq("01025")
      expect(value).to eq(2)
    end
  end

  context "#get_card" do
    it "calls the single card API" do
      ret = ArkhamDbHelper.get_card(10019)
      expect(ret["imagesrc"]).to eq("/bundles/cards/10019.png")
    end

    it "returns nil with invalid card_id" do
      ret = ArkhamDbHelper.get_card(12345)
      expect(ret).to eq nil
    end
  end

  context "#get_card_image_url" do
    it "returns a valid image URL" do
      ret = ArkhamDbHelper.get_card_image_url(10019)
      expect(ret).to eq "https://arkhamdb.com/bundles/cards/10019.png"
    end

    it "returns nil with invalid card_id" do
      ret = ArkhamDbHelper.get_card_image_url(12345)
      expect(ret).to eq nil
    end
  end
  # it "calls the all cards API" do
  #   ret = ArkhamDbHelper.get_all_cards()
  #   # pp ret
  # end
end
