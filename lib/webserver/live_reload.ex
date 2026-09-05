defmodule Webserver.LiveReload do
  @moduledoc """
  Plug that provides a Server-Sent Events (SSE) endpoint for live reloading.
  """
  @behaviour Plug
  import Plug.Conn

  alias Webserver.LiveReload.PubSub

  def init(opts), do: opts

  def call(conn, _opts) do
    # The route is compiled unconditionally, but PubSub is only supervised when
    # live reload is on. Without this check a production request commits a
    # chunked 200 and then dies subscribing to a process that was never
    # started, leaving the client a truncated body and the log a crash.
    if Process.whereis(PubSub) do
      stream(conn)
    else
      send_resp(conn, 404, "Not Found")
    end
  end

  defp stream(conn) do
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
