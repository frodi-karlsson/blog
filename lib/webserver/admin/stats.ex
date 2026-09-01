defmodule Webserver.Admin.Stats do
  @moduledoc """
  Assembles the merged admin stats payload: request metrics, BEAM stats, and
  cache counters with a derived hit rate.

  `Store.stats/1` stays a raw counter accessor; the ratio is derived here so the
  cache has no opinion about presentation.
  """

  alias Webserver.Content.Store
  alias Webserver.Telemetry.Metrics

  @spec snapshot() :: map()
  def snapshot do
    Metrics.snapshot()
    |> Map.put(:cache, cache_stats())
  end

  defp cache_stats do
    stats = Store.stats()
    Map.put(stats, :hit_rate, hit_rate(stats.hits, stats.misses))
  end

  # nil rather than 0.0 when nothing has been served yet: "no data" and "every
  # lookup missed" are different states and shouldn't render the same.
  defp hit_rate(0, 0), do: nil
  defp hit_rate(hits, misses), do: Float.round(hits / (hits + misses), 4)
end
