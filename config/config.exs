import Config

config :webserver,
  template_reader: Webserver.TemplateServer.TemplateReader.File,
  port: 4040,
  base_url: "./priv/templates",
  mtime_check_interval: :timer.seconds(60)

import_config "#{config_env()}.exs"
