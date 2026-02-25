import Config

config :webserver,
  template_reader: Webserver.TemplateServer.TemplateReader.File,
  port: 4040,
  base_url: "./priv/templates",
  external_url: "https://blog.frodikarlsson.com",
  mtime_check_interval: :timer.seconds(60),
  live_reload: false,
  inject_assets: true

config :dart_sass,
  version: "1.83.4",
  default: [
    args: ~w(css/app.scss:../priv/static/css/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
