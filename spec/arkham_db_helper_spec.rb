require "pp"
require "rails_helper"

RSpec.describe "ArkhamDbHelper" do
  it "calls the deck API" do
    ret = ArkhamDbHelper.get_cards_from_deck_id(48985)
    #pp ret
    expect(ret.count).to eq(20)
    key, value = ret.first
    expect(key).to eq("01025")
    expect(value).to eq(2)
  end

  it "calls the single card API" do
    ret = ArkhamDbHelper.get_card(10019)
    #pp ret
    expect(ret["imagesrc"]).to eq("/bundles/cards/10019.png")
  end

  it "calls the single card API for an image URL" do
    ret = ArkhamDbHelper.get_card_image_url(10019)
    #pp ret
    expect(ret).to eq("https://arkhamdb.com/bundles/cards/10019.png")
  end

  it "calls the all cards API" do
    ret = ArkhamDbHelper.get_all_cards()
    #pp ret
    
  end
end