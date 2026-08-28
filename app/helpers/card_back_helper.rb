module CardBackHelper
  DIR = Rails.root.join("app/assets/images/card_backs")

  # Mythos-faction cards (the shuffled encounter deck: enemies, treacheries,
  # etc.) share the "Mythos" back; neutral-faction scenario cards (story
  # assets/allies granted mid-campaign, and anything else) use "Standard".
  BACK_BY_FACTION = {
    "mythos" => "mythos.png"
  }.freeze

  def self.path_for(faction_code)
    filename = BACK_BY_FACTION.fetch(faction_code, "standard.png")
    candidate = DIR.join(filename)
    File.exist?(candidate) ? candidate.to_s : DIR.join("generic.png").to_s
  end
end
