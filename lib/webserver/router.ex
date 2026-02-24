defmodule Webserver.Router do
  @moduledoc """
  Main router. Serves static files from `priv/static`, exposes admin cache
  endpoints at `/admin/*`, a health check at `/health`, and forwards all
  other requests to `Webserver.Server`.
  """

  use Plug.Router
  import Plug.Conn

  alias Webserver.Server
  alias Webserver.TemplateServer.Cache

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

  get "/health" do
    json(conn, 200, %{status: "ok"})
  end

  get "/admin/cache/stats" do
    stats = Cache.stats()
    json(conn, 200, stats)
  end

  get("/live-reload", to: Webserver.LiveReload)

  post "/admin/cache/refresh" do
    case Cache.force_refresh() do
      :ok -> json(conn, 200, %{status: "cache refreshed"})
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  forward("/", to: Server)

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
