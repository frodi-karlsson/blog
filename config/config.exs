import Config

config :webserver, :template_reader, TemplateServer.TemplateReader.File
config :webserver, :port, 4040
config :webserver, :base_url, "./priv/templates"

config_env = config_env()

import_config "#{config_env()}.exs"
