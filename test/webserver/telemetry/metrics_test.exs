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

  defp record(path, status, us) do
    Metrics.handle_event(
      [:webserver, :request, :stop],
      %{duration: System.convert_time_unit(us, :microsecond, :native)},
      %{path: path, status: status},
      nil
    )
  end

  test "should report server start and uptime" do
    snapshot = Metrics.snapshot()

    assert snapshot.server.started_at_ms == 0
    assert snapshot.server.started_at == "1970-01-01T00:00:00.000Z"
    assert snapshot.server.uptime_ms > 0
  end

  test "should separate all-time mean from the rolling window" do
    for us <- [1_000, 2_000, 3_000, 4_000, 5_000], do: record("/", 200, us)

    stats = Metrics.snapshot().requests.by_path["/"]

    assert stats.count == 5
    assert stats.all_time_mean_ms == 3.0

    assert stats.window == %{
             size: 5,
             mean_ms: 3.0,
             median_ms: 3.0,
             p95_ms: 5.0,
             min_ms: 1.0,
             max_ms: 5.0
           }
  end

  test "should count requests by status class" do
    record("/", 200, 1_000)
    record("/", 204, 1_000)
    record("/", 404, 1_000)
    record("/", 500, 1_000)

    stats = Metrics.snapshot().requests.by_path["/"]

    assert stats.status == %{"2xx" => 2, "4xx" => 1, "5xx" => 1}
    assert stats.count == 4
  end

  test "should keep status counts separate per path" do
    record("/", 500, 1_000)
    record("/health", 200, 1_000)

    by_path = Metrics.snapshot().requests.by_path

    assert by_path["/"].status == %{"5xx" => 1}
    assert by_path["/health"].status == %{"2xx" => 1}
  end

  test "should total requests across paths and rank the slowest" do
    record("/", 200, 1_000)
    record("/health", 200, 9_000)
    record("/health", 200, 9_000)

    requests = Metrics.snapshot().requests

    assert requests.total == 3
    assert [%{path: "/health", p95_ms: 9.0}, %{path: "/", p95_ms: 1.0}] = requests.slowest_paths
  end

  test "should report a request rate over the recent window" do
    for _ <- 1..60, do: record("/", 200, 1_000)

    assert Metrics.snapshot().requests.req_per_sec == 1.0
  end

  test "should bound the window to the sample size" do
    for _ <- 1..300, do: record("/", 200, 1_000)

    stats = Metrics.snapshot().requests.by_path["/"]

    assert stats.count == 300
    assert stats.window.size == 256
  end

  test "should ignore unknown paths" do
    record("/definitely-not-a-real-page", 200, 1_000)

    refute Map.has_key?(Metrics.snapshot().requests.by_path, "/definitely-not-a-real-page")
  end

  test "should not raise on malformed events" do
    assert Metrics.handle_event([:webserver, :request, :stop], %{}, %{}, nil) == :ok

    assert Metrics.handle_event(
             [:webserver, :request, :stop],
             %{duration: nil},
             %{path: "/", status: "200"},
             nil
           ) == :ok

    assert Metrics.snapshot().requests.by_path == %{}
  end

  test "should include BEAM stats" do
    beam = Metrics.snapshot().beam

    assert beam.process_count > 0
    assert beam.schedulers > 0
    assert beam.memory_mb.total > 0
  end
end
