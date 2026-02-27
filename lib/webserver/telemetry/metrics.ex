defmodule Webserver.Telemetry.Metrics do
  @moduledoc false

  @table :webserver_metrics
  @handler_id :webserver_request_metrics
  @sample_size 256

  def setup do
    ensure_table()
    ensure_server_started()
    ensure_handler_attached()
    :ok
  end

  def snapshot do
    ensure_table()

    started_at_ms = lookup(:server_started_at_ms)

    started_at =
      case started_at_ms do
        nil -> nil
        ms -> ms |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()
      end

    %{
      server_started_at_ms: started_at_ms,
      server_started_at: started_at,
      server_started: started_at,
      response_time_ms_by_path: response_time_ms_by_path()
    }
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

  def handle_event([:webserver, :request, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration)
    path = Map.get(metadata, :path)
    status = Map.get(metadata, :status)

    if is_integer(duration) and is_binary(path) and is_integer(status) and valid_path?(path) do
      duration_us = System.convert_time_unit(duration, :native, :microsecond)

      :ets.update_counter(
        @table,
        {:endpoint, path},
        [{2, 1}, {3, duration_us}],
        {{:endpoint, path}, 0, 0}
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
    end
  end

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  defp response_time_ms_by_path do
    ensure_table()

    @table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn
      {{:endpoint, path}, count, total_us}, acc when count > 0 and is_integer(total_us) ->
        samples = samples_for_path(path)

        stats =
          case samples do
            [] ->
              %{
                mean: Float.round(total_us / count / 1000, 3),
                median: nil,
                p95: nil
              }

            _ ->
              sorted = Enum.sort(samples)
              n = length(sorted)
              median_us = percentile(sorted, n, 0.5)
              p95_us = percentile(sorted, n, 0.95)

              %{
                mean: Float.round(total_us / count / 1000, 3),
                median: Float.round(median_us / 1000, 3),
                p95: Float.round(p95_us / 1000, 3)
              }
          end

        Map.put(acc, path, stats)

      _, acc ->
        acc
    end)
  end

  defp samples_for_path(path) do
    0..(@sample_size - 1)
    |> Enum.reduce([], fn i, acc ->
      case :ets.lookup(@table, {:sample, path, i}) do
        [{{:sample, ^path, ^i}, us}] when is_integer(us) -> [us | acc]
        _ -> acc
      end
    end)
  end

  defp percentile(sorted, n, p) when n > 0 do
    idx = trunc(Float.ceil(p * n)) - 1
    Enum.at(sorted, max(idx, 0))
  end

  defp valid_path?(path) do
    path in ["/", "/health", "/robots.txt", "/sitemap.xml"] or in_page_registry?(path)
  end

  defp in_page_registry?(path) do
    case :ets.lookup(Webserver.TemplateServer.Cache, :page_registry) do
      [{:page_registry, pages}] when is_list(pages) ->
        Enum.any?(pages, fn
          %{"path" => ^path} -> true
          _ -> false
        end)

      _ ->
        false
    end
  rescue
    ArgumentError ->
      false
  end
end
