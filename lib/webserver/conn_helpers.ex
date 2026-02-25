defmodule Webserver.ConnHelpers do
  @moduledoc """
  Shared helpers for working with Plug connections.
  """
  import Plug.Conn

  @doc """
  Sends a JSON response with the given status and data.
  """
  def json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
