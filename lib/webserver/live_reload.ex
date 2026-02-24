defmodule Webserver.LiveReload do
  @moduledoc """
  Plug that provides a Server-Sent Events (SSE) endpoint for live reloading.
  """
  @behaviour Plug
  import Plug.Conn

  alias Webserver.LiveReload.PubSub

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    PubSub.subscribe(self())

    loop(conn)
  end

  defp loop(conn) do
    receive do
      {:reload, type} ->
        case chunk(conn, "data: #{Jason.encode!(%{type: type})}\n\n") do
          {:ok, new_conn} -> loop(new_conn)
          {:error, _} -> conn
        end
    after
      30_000 ->
        case chunk(conn, ": ping\n\n") do
          {:ok, new_conn} -> loop(new_conn)
          {:error, _} -> conn
        end
    end
  end
end
