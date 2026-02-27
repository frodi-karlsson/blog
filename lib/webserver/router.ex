defmodule Webserver.Router do
  @moduledoc """
  Main router. Serves static files from `priv/static`, exposes admin cache
  endpoints at `/admin/*`, a health check at `/health`, and forwards all
  other requests to `Webserver.Server`.
  """

  use Plug.Router
  import Plug.Conn
  import Webserver.ConnHelpers

  alias Webserver.AdminRouter
  alias Webserver.Server
  alias Webserver.Sitemap

  @static_cache_control Application.compile_env(
                          :webserver,
                          :static_cache_control,
                          "public, max-age=0, must-revalidate"
                        )

  plug(Plug.RequestId)
  plug(Webserver.Telemetry.RequestPlug)
  plug(Plug.Logger)
  plug(Plug.Head)

  plug(Plug.Static,
    at: "/static",
    from: {:webserver, "priv/static"},
    gzip: false,
    headers: %{"cache-control" => @static_cache_control}
  )

  plug(:match)
  plug(:dispatch)

  get "/robots.txt" do
    external_url = Application.get_env(:webserver, :external_url, "https://example.com")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "User-agent: *\nAllow: /\n\nSitemap: #{external_url}/sitemap.xml\n")
  end

  get "/health" do
    json(conn, 200, %{status: "ok"})
  end

  get("/live-reload", to: Webserver.LiveReload)

  get("/sitemap.xml", to: Sitemap)

  forward("/admin", to: AdminRouter)

  @redirects %{
    "/building-an-elixir-webserver-from-scratch" => "/bespoke-elixir-web-framework"
  }

  for {old_path, new_path} <- @redirects do
    get old_path do
      conn
      |> put_resp_header("location", unquote(new_path))
      |> send_resp(301, "")
    end
  end

  forward("/", to: Server)
end
