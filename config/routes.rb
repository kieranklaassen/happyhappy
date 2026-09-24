Rails.application.routes.draw do
  # --- Sign in with Every (U2). /auth/every itself is the OmniAuth middleware. ---
  resource :session, only: %i[new destroy]
  get "auth/every/callback", to: "sessions/every#create"
  draw :dev_login if Rails.env.development?

  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Slack connector (U4): Events API request URL, signature-authenticated.
  post "webhooks/slack/events" => "webhooks/slack#create", as: :webhooks_slack_events

  # PWA surface (docs/modules/pwa.md): Rails' built-in controller renders
  # app/views/pwa/*, public and outside the Inertia auth gate. Formats are pinned
  # so a mismatched request 404s at routing instead of raising MissingTemplate
  # (500) in the view layer: /manifest.json is the only manifest URL, and the
  # extension-less /service-worker defaults to js because Rails collapses
  # browser-like Accept headers to html.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest, format: true, constraints: { format: "json" }
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker,
    defaults: { format: :js }, constraints: { format: "js" }

  # U10: feed, item timeline, corrections, product overview
  resources :items, only: %i[index show] do
    resource :labels, only: :update, controller: "item_labels"
    resource :status, only: :update, controller: "item_statuses"
  end
  resources :products, only: [] do
    resource :overview, only: :show, controller: "product_overviews"
  end
  # Postmark inbound email webhook (U7)
  post "webhooks/postmark" => "webhooks/postmark#create", as: :postmark_webhook

  # Defines the root path route ("/")
  root "home#index"
end
