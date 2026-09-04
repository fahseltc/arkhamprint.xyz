Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"

  get "/faq", to: "faq#index"
  get "/changelog", to: "changelog#index"

  resources :pdf_jobs, only: [ :create, :show ] do
    member do
      get :download
      post :cancel
    end
  end
end
