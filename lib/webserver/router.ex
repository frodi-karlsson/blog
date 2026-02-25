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

  plug(Plug.RequestId)
  plug(Plug.Logger)
  plug(Plug.Head)

  plug(Plug.Static,
    at: "/static",
    from: {:webserver, "priv/static"},
    gzip: false
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

  forward("/", to: Server)
end
