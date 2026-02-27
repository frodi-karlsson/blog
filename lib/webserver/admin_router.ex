defmodule Webserver.AdminRouter do
  @moduledoc """
  Router for administrative tasks and pages.
  Middleware for authentication can be added here.
  """
  use Plug.Router
  import Webserver.ConnHelpers

  alias Webserver.Server
  alias Webserver.Telemetry.Metrics
  alias Webserver.TemplateServer.Cache

  plug(:match)
  plug(:authenticate)
  plug(:dispatch)

  defp authenticate(conn, _opts) do
    username = Application.fetch_env!(:webserver, :admin_username)
    password = Application.fetch_env!(:webserver, :admin_password)

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  get "/cache/stats" do
    stats = Cache.stats()
    json(conn, 200, stats)
  end

  get "/stats" do
    json(conn, 200, Metrics.snapshot())
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
end
