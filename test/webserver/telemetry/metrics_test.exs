defmodule Webserver.Telemetry.MetricsTest do
  use ExUnit.Case, async: false

  alias Webserver.Telemetry.Metrics

  @table :webserver_metrics

  setup do
    Metrics.setup()

    :ets.delete_all_objects(@table)
    :ets.insert(@table, {:server_started_at_ms, 0})

    :ok
  end

  test "should include server_started_at and per-path stats" do
    for us <- [1_000, 2_000, 3_000, 4_000, 5_000] do
      duration_native = System.convert_time_unit(us, :microsecond, :native)

      Metrics.handle_event(
        [:webserver, :request, :stop],
        %{duration: duration_native},
        %{path: "/", status: 200},
        nil
      )
    end

    snapshot = Metrics.snapshot()

    assert snapshot.server_started_at_ms == 0
    assert snapshot.server_started_at == "1970-01-01T00:00:00.000Z"

    assert snapshot.response_time_ms_by_path["/"] == %{mean: 3.0, median: 3.0, p95: 5.0}
  end

  test "should ignore unknown paths" do
    duration_native = System.convert_time_unit(1_000, :microsecond, :native)

    Metrics.handle_event(
      [:webserver, :request, :stop],
      %{duration: duration_native},
      %{path: "/definitely-not-a-real-page", status: 200},
      nil
    )

    snapshot = Metrics.snapshot()
    refute Map.has_key?(snapshot.response_time_ms_by_path, "/definitely-not-a-real-page")
  end
end
