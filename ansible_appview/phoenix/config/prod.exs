import Config

# Production values are supplied at runtime in runtime.exs (DATABASE_URL,
# RELAY_BASE_URL, PORT). This file intentionally holds only compile-time prod
# defaults.
config :logger, level: :info
