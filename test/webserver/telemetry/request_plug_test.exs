defmodule Webserver.Telemetry.RequestPlugTest do
  use ExUnit.Case, async: true

  alias Plug.Test
  alias Webserver.Telemetry.RequestPlug

  test "should emit request telemetry on response" do
    handler_id = {__MODULE__, make_ref()}

    try do
      :ok =
        :telemetry.attach(
          handler_id,
          [:webserver, :request, :stop],
          fn _event, _measurements, metadata, test_pid ->
            send(test_pid, {:telemetry, metadata})
          end,
          self()
        )

      _conn =
        "GET"
        |> Test.conn("/health")
        |> RequestPlug.call([])
        |> Plug.Conn.send_resp(200, "ok")

      assert_receive {:telemetry, %{path: "/health", status: 200}}, 500
    after
      :telemetry.detach(handler_id)
    end
  end
end
