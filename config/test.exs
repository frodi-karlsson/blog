import Config

config :webserver,
  template_reader: Webserver.TemplateServer.TemplateReader.Sandbox,
  port: 4444,
  template_dir: "/priv/templates",
  mtime_check_interval: 0,
  admin_username: "admin",
  admin_password: "admin"
