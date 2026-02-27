import Config

config :webserver, static_cache_control: "public, max-age=31536000, immutable"

config :dart_sass,
  default: [
    args: ~w(css/app.scss:../priv/static/css/app.css --style=compressed --no-source-map),
    cd: Path.expand("../assets", __DIR__)
  ]
