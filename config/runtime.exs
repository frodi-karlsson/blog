import Config

if config_env() == :prod do
  config :webserver,
    template_dir: Path.join(:code.priv_dir(:webserver), "templates"),
    port: String.to_integer(System.get_env("PORT") || "4040"),
    external_url: System.get_env("EXTERNAL_URL") || "https://blog.frodikarlsson.com",
    live_reload: false,
    admin_username: System.fetch_env!("ADMIN_USERNAME"),
    admin_password: System.fetch_env!("ADMIN_PASSWORD")
end
