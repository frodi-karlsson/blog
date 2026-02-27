defmodule Webserver.Telemetry.RequestPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:webserver, :request, :stop],
        %{duration: duration},
        %{method: conn.method, path: conn.request_path, status: conn.status}
      )

      conn
    end)
  end
end
