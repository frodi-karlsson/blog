defmodule Webserver.AdminRouter do
  @moduledoc """
  Router for administrative tasks and pages.
  Middleware for authentication can be added here.
  """
  use Plug.Router
  import Webserver.ConnHelpers

  alias Webserver.Admin.Stats
  alias Webserver.Admin.StatsPage
  alias Webserver.Content.Store
  alias Webserver.Server

  plug(:match)
  plug(:authenticate)
  plug(:dispatch)

  defp authenticate(conn, _opts) do
    username = Application.fetch_env!(:webserver, :admin_username)
    password = Application.fetch_env!(:webserver, :admin_password)

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  # Kept for compatibility; /stats.json now carries these under :cache too.
  get "/cache/stats" do
    stats = Store.stats()
    json(conn, 200, stats)
  end

  get "/stats.json" do
    json(conn, 200, Stats.snapshot())
  end

  get "/stats" do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, StatsPage.render(Stats.snapshot()))
  end

  post "/cache/refresh" do
    case Store.force_refresh() do
      :ok -> json(conn, 200, %{status: "cache refreshed"})
      {:error, reason} -> json(conn, 500, %{error: inspect(reason)})
    end
  end

  # This catch-all inside the admin scope ensures admin templates are served
  # e.g. /admin/design-system -> index.html (with admin prefix)
  forward("/", to: Server)
end
