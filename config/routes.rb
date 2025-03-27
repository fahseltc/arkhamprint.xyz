require "sidekiq/web"

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  get "/from_deck", to: "card#from_deck"
  get "/from_card_list", to: "card#from_card_list"

  get "/faq", to: "faq#index"

  get "/job/from_deck"
  get "/job/from_card_list"
  get "/job/download"
  get "/job/status"
  # get "/job/download", to:"job#download"


  mount Sidekiq::Web => "/sidekiq" # access it at http://localhost:3000/sidekiq
end
