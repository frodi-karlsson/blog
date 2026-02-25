import Config

config :webserver,
  template_reader: Webserver.TemplateServer.TemplateReader.Sandbox,
  port: 4444,
  base_url: "/priv/templates",
  mtime_check_interval: 0,
  inject_assets: false,
  admin_username: "admin",
  admin_password: "admin"
