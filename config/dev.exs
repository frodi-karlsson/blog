import Config

config :webserver,
  live_reload: true,
  mtime_check_interval: 0

config :dart_sass,
  version: "1.83.4",
  default: [
    args: ~w(css/app.scss:../priv/static/css/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
