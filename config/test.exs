import Config

config :webserver, :template_reader, TemplateServer.TemplateReader.Sandbox
config :webserver, :port, 4444
config :webserver, :base_url, "/priv/templates"
config :webserver, :mtime_check_interval, 0
