require "sidekiq/web" # require the web UI
Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  # post "/from_deck", to: "card#from_deck"
  # get "/from_card_list", to: "card#from_card_list"

  get "/faq", to: "faq#index"

  resources :pdf_jobs, only: [ :create, :show ] do
    member do
      get :download
    end
  end


  mount Sidekiq::Web => "/sidekiq" # access it at http://localhost:3000/sidekiq
end
