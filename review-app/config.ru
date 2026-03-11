# frozen_string_literal: true

require_relative "app"

# Mount the review app at root and the dashboard at /dashboard.
# Both share the same Postgres session store via Spurline.config.
app = Rack::URLMap.new(
  "/"          => ReviewApp,
  "/dashboard" => Spurline::Dashboard::App
)

run app
