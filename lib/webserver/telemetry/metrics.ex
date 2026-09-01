defmodule Webserver.Telemetry.Metrics do
  @moduledoc """
  Request metrics collected from `[:webserver, :request, :stop]` telemetry.

  Two populations are tracked per path and reported separately, because mixing
  them is misleading:

    * all-time totals (`count`, `all_time_mean_ms`), accumulated since boot
    * a rolling window of the last 256 requests, used for median/p95

  Throughput uses a 60-slot ring of per-second counters, so `req_per_sec` covers
  the last minute rather than the whole uptime.
  """

  alias Webserver.Content.Query

  @table :webserver_metrics
  @handler_id :webserver_request_metrics
  @sample_size 256
  @rate_window_sec 60

  def setup do
    ensure_table()
    ensure_server_started()
    ensure_handler_attached()
    :ok
  end

  @doc """
  Full metrics payload: server, BEAM, and per-path request stats.
  """
  def snapshot do
    ensure_table()

    started_at_ms = lookup(:server_started_at_ms)
    by_path = response_time_by_path()

    %{
      server: server_stats(started_at_ms),
      beam: beam_stats(),
      requests: %{
        total: total_requests(by_path),
        req_per_sec: req_per_sec(),
        by_path: by_path,
        slowest_paths: slowest_paths(by_path)
      }
    }
  end

  defp server_stats(nil), do: %{started_at_ms: nil, started_at: nil, uptime_ms: nil}

  defp server_stats(started_at_ms) do
    %{
      started_at_ms: started_at_ms,
      started_at: started_at_ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601(),
      uptime_ms: System.system_time(:millisecond) - started_at_ms
    }
  end

  defp beam_stats do
    memory = :erlang.memory()

    %{
      memory_mb: %{
        total: bytes_to_mb(memory[:total]),
        processes: bytes_to_mb(memory[:processes]),
        binary: bytes_to_mb(memory[:binary]),
        ets: bytes_to_mb(memory[:ets])
      },
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: :erlang.system_info(:schedulers_online)
    }
  end

  defp bytes_to_mb(nil), do: nil
  defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)

  defp total_requests(by_path) do
    Enum.reduce(by_path, 0, fn {_path, stats}, acc -> acc + stats.count end)
  end

  defp slowest_paths(by_path) do
    by_path
    |> Enum.reject(fn {_path, stats} -> is_nil(stats.window.p95_ms) end)
    |> Enum.sort_by(fn {_path, stats} -> stats.window.p95_ms end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {path, stats} -> %{path: path, p95_ms: stats.window.p95_ms} end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: :auto
        ])

      _ ->
        :ok
    end
  end

  defp ensure_server_started do
    :ets.insert_new(@table, {:server_started_at_ms, System.system_time(:millisecond)})
  end

  defp ensure_handler_attached do
    case :telemetry.attach(
           @handler_id,
           [:webserver, :request, :stop],
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc """
  Records one request. Never raises: a telemetry handler that raises is detached
  permanently by `:telemetry`, which would silently stop all collection.
  """
  def handle_event([:webserver, :request, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration)
    path = Map.get(metadata, :path)
    status = Map.get(metadata, :status)

    if is_integer(duration) and is_binary(path) and is_integer(status) and valid_path?(path) do
      duration_us = System.convert_time_unit(duration, :native, :microsecond)
      record(path, status, duration_us)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp record(path, status, duration_us) do
    :ets.update_counter(
      @table,
      {:endpoint, path},
      [{2, 1}, {3, duration_us}],
      {{:endpoint, path}, 0, 0}
    )

    :ets.update_counter(
      @table,
      {:status, path, div(status, 100)},
      {2, 1},
      {{:status, path, div(status, 100)}, 0}
    )

    idx =
      :ets.update_counter(
        @table,
        {:sample_idx, path},
        {2, 1},
        {{:sample_idx, path}, 0}
      )

    slot = rem(idx - 1, @sample_size)
    :ets.insert(@table, {{:sample, path, slot}, duration_us})

    record_rate()
  end

  # 60-slot ring of per-second counters. Two processes crossing a second
  # boundary can both reset the slot, losing at most a request from the rate
  # estimate; the trade is a fixed 60-row footprint with no pruning pass.
  defp record_rate do
    now = System.system_time(:second)
    slot = rem(now, @rate_window_sec)

    case :ets.lookup(@table, {:rate, slot}) do
      [{_, ^now, _}] -> :ets.update_counter(@table, {:rate, slot}, {3, 1})
      _ -> :ets.insert(@table, {{:rate, slot}, now, 1})
    end
  end

  defp req_per_sec do
    now = System.system_time(:second)
    cutoff = now - @rate_window_sec

    total =
      @table
      |> :ets.select([{{{:rate, :_}, :"$1", :"$2"}, [{:>, :"$1", cutoff}], [{{:"$1", :"$2"}}]}])
      |> Enum.reduce(0, fn {_sec, count}, acc -> acc + count end)

    Float.round(total / @rate_window_sec, 3)
  end

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  defp response_time_by_path do
    ensure_table()

    @table
    |> :ets.select([
      {{{:endpoint, :"$1"}, :"$2", :"$3"}, [{:>, :"$2", 0}], [{{:"$1", :"$2", :"$3"}}]}
    ])
    |> Enum.reduce(%{}, fn {path, count, total_us}, acc ->
      Map.put(acc, path, path_stats(path, count, total_us))
    end)
  end

  defp path_stats(path, count, total_us) do
    %{
      count: count,
      status: status_counts(path),
      all_time_mean_ms: us_to_ms(total_us / count),
      window: window_stats(samples_for_path(path))
    }
  end

  defp window_stats([]) do
    %{size: 0, mean_ms: nil, median_ms: nil, p95_ms: nil, min_ms: nil, max_ms: nil}
  end

  defp window_stats(samples) do
    sorted = Enum.sort(samples)
    n = length(sorted)

    %{
      size: n,
      mean_ms: us_to_ms(Enum.sum(sorted) / n),
      median_ms: us_to_ms(percentile(sorted, n, 0.5)),
      p95_ms: us_to_ms(percentile(sorted, n, 0.95)),
      min_ms: us_to_ms(List.first(sorted)),
      max_ms: us_to_ms(List.last(sorted))
    }
  end

  defp us_to_ms(us), do: Float.round(us / 1000, 3)

  defp status_counts(path) do
    @table
    |> :ets.select([
      {{{:status, path, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.reduce(%{}, fn {class, count}, acc ->
      Map.put(acc, "#{class}xx", count)
    end)
  end

  defp samples_for_path(path) do
    :ets.select(@table, [
      {{{:sample, path, :_}, :"$1"}, [], [:"$1"]}
    ])
  end

  defp percentile(sorted, n, p) when n > 0 do
    idx = trunc(Float.ceil(p * n)) - 1
    Enum.at(sorted, max(idx, 0))
  end

  defp valid_path?(path) do
    path in ["/", "/health", "/robots.txt", "/sitemap.xml"] or Query.page_path?(path)
  end
end
