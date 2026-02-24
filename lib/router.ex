defmodule Router do
  @moduledoc """
  Router that serves static files from priv/static and forwards other requests to Server.
  Static files are served at /static/* from priv/static/ directory.
  Admin endpoints for cache statistics at /admin/*
  All other requests are handled by the Server plug.
  """

  use Plug.Router
  import Plug.Conn

  plug(Plug.Static,
    at: "/static",
    from: {:webserver, "priv/static"},
    gzip: false
  )

  plug(:match)
  plug(:dispatch)

  get "/admin/cache/stats" do
    stats = TemplateServer.Cache.stats()
    json(conn, 200, stats)
  end

  post "/admin/cache/refresh" do
    :ok = TemplateServer.Cache.force_refresh()
    json(conn, 200, %{status: "cache refreshed"})
  end

  forward("/", to: Server)

  defp json(conn, status, data) do
    json_body = encode_json(data)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json_body)
  end

  defp encode_json(map) when is_map(map) do
    entries = Enum.map(map, fn {k, v} -> "#{k}:#{encode_json(v)}" end)
    "{#{Enum.join(entries, ",")}}"
  end

  defp encode_json(val) when is_integer(val), do: Integer.to_string(val)
  defp encode_json(val) when is_binary(val), do: "\"#{val}\""
  defp encode_json(val), do: "\"#{val}\""
end
