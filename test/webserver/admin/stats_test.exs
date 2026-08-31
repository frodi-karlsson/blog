defmodule Webserver.Admin.StatsTest do
  use ExUnit.Case, async: false

  alias Webserver.Admin.Stats
  alias Webserver.Admin.StatsPage

  test "should merge server, beam, cache and request sections" do
    snapshot = Stats.snapshot()

    assert Map.has_key?(snapshot, :server)
    assert Map.has_key?(snapshot, :beam)
    assert Map.has_key?(snapshot, :cache)
    assert Map.has_key?(snapshot, :requests)
  end

  test "should derive a cache hit rate from the raw counters" do
    cache = Stats.snapshot().cache

    assert Map.has_key?(cache, :hits)
    assert Map.has_key?(cache, :misses)

    case cache.hit_rate do
      nil -> assert cache.hits == 0 and cache.misses == 0
      rate -> assert rate >= 0.0 and rate <= 1.0
    end
  end

  describe "dashboard rendering" do
    test "should render tiles and an empty-state when no requests are recorded" do
      html = StatsPage.render(empty_snapshot())

      assert html =~ ~s(data-testid="stat-tiles")
      assert html =~ ~s(data-testid="stats-empty")
      refute html =~ ~s(data-testid="stats-path-table")
      refute html =~ "Stats unavailable."
    end

    test "should render a row per path, busiest first" do
      html =
        StatsPage.render(
          put_in(empty_snapshot().requests.by_path, %{
            "/" => path_stats(10, %{"2xx" => 10}),
            "/health" => path_stats(99, %{"2xx" => 98, "5xx" => 1})
          })
        )

      assert html =~ ~s(data-testid="stats-path-table")
      refute html =~ ~s(data-testid="stats-empty")

      # Busiest path first. Match the row cell specifically -- a bare
      # `<a href="/">` also matches the "Back to Blog" link in the header.
      {health_at, _} = :binary.match(html, ~s(<th scope="row"><a href="/health">))
      {root_at, _} = :binary.match(html, ~s(<th scope="row"><a href="/">))
      assert health_at < root_at

      assert html =~ "5xx 1"
    end

    test "should show a dash rather than a number when the window is empty" do
      html =
        StatsPage.render(
          put_in(empty_snapshot().requests.by_path, %{
            "/" => %{
              count: 1,
              status: %{},
              all_time_mean_ms: 1.0,
              window: %{
                size: 0,
                mean_ms: nil,
                median_ms: nil,
                p95_ms: nil,
                min_ms: nil,
                max_ms: nil
              }
            }
          })
        )

      assert html =~ "—"
      refute html =~ "Stats unavailable."
    end
  end

  defp empty_snapshot do
    %{
      server: %{started_at_ms: 0, started_at: "1970-01-01T00:00:00.000Z", uptime_ms: 90_061_000},
      beam: %{
        memory_mb: %{total: 42.0, processes: 10.0, binary: 1.0, ets: 2.0},
        process_count: 60,
        process_limit: 262_144,
        run_queue: 0,
        schedulers: 8
      },
      cache: %{
        hits: 10,
        misses: 2,
        revalidations: 1,
        revalidation_errors: 0,
        hit_rate: 0.8333
      },
      requests: %{total: 0, req_per_sec: 0.0, by_path: %{}, slowest_paths: []}
    }
  end

  defp path_stats(count, status) do
    %{
      count: count,
      status: status,
      all_time_mean_ms: 2.0,
      window: %{size: count, mean_ms: 2.0, median_ms: 1.5, p95_ms: 5.0, min_ms: 1.0, max_ms: 9.0}
    }
  end
end
