defmodule Webserver.AdminRouter do
  @moduledoc """
  Router for administrative tasks and pages.
  Middleware for authentication can be added here.
  """
  use Plug.Router

  alias Webserver.Server
  alias Webserver.TemplateServer.Cache

  plug(:match)
  plug(:dispatch)

  get "/cache/stats" do
    stats = Cache.stats()
    json(conn, 200, stats)
  end

  post "/cache/refresh" do
    case Cache.force_refresh() do
      :ok -> json(conn, 200, %{status: "cache refreshed"})
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  # This catch-all inside the admin scope ensures admin templates are served
  # e.g. /admin/design-system -> index.html (with admin prefix)
  forward("/", to: Server)

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
