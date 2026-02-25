import Config

if config_env() == :prod do
  config :webserver,
    base_url: Path.join(:code.priv_dir(:webserver), "templates"),
    port: String.to_integer(System.get_env("PORT") || "4040"),
    admin_username: System.fetch_env!("ADMIN_USERNAME"),
    admin_password: System.fetch_env!("ADMIN_PASSWORD")
end
