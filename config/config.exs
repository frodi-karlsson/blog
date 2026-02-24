import Config

config :webserver, :template_reader, TemplateServer.TemplateReader.File
config :webserver, :port, 4040
config :webserver, :base_url, "./priv/templates"
config :webserver, :mtime_check_interval, :timer.seconds(60)

config_env = config_env()

import_config "#{config_env()}.exs"
