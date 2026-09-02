defmodule Webserver.Admin.StatsPage do
  @moduledoc """
  Renders the admin stats dashboard at request time, using the same
  layout/partial pipeline as the rest of the site.
  """

  alias Webserver.Content.Store
  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  @spec render(map()) :: String.t()
  def render(snapshot) do
    {:ok, partials} = Store.get_partials()
    {:ok, compiled_partials} = Store.get_compiled_partials()
    template_dir = Application.fetch_env!(:webserver, :template_dir)

    body = """
    <div class="stack stack--loose">
      <header class="stack stack--tight" data-testid="stats-header">
        <p class="text-subtle"><a href="/">← Back to Blog</a></p>
        <h1>Stats</h1>
      </header>

      <div class="grid" data-testid="stat-tiles">#{tiles(snapshot)}</div>

      #{path_table(snapshot)}
    </div>
    """

    template = """
    <% layout.html %>
      <slot:title>Stats</slot:title>
      <slot:description>Server and request metrics</slot:description>
      <slot:canonical></slot:canonical>
      <slot:og_type>website</slot:og_type>
      <slot:body>#{body}</slot:body>
    <%/ layout.html %>
    """

    case Parser.parse(%ParseInput{
           file: template,
           template_dir: template_dir,
           partials: partials,
           compiled_partials: compiled_partials
         }) do
      {:ok, html} -> html
      _ -> "<p>Stats unavailable.</p>"
    end
  end

  defp tiles(snapshot) do
    cache = snapshot.cache

    [
      {"Uptime", format_uptime(snapshot.server.uptime_ms)},
      {"Requests", format_int(snapshot.requests.total)},
      {"Req/sec (1m)", to_string(snapshot.requests.req_per_sec)},
      {"Cache hit rate", format_rate(cache.hit_rate)},
      {"Cache hits / misses", "#{format_int(cache.hits)} / #{format_int(cache.misses)}"},
      {"Revalidation errors", format_int(cache.revalidation_errors)},
      {"Memory", "#{snapshot.beam.memory_mb.total} MB"},
      {"Processes", format_int(snapshot.beam.process_count)},
      {"Run queue", format_int(snapshot.beam.run_queue)}
    ]
    |> Enum.map_join("\n", fn {label, value} ->
      """
      <div class="stat-tile">
        <span class="stat-tile__label">#{esc(label)}</span>
        <span class="stat-tile__value">#{esc(value)}</span>
      </div>
      """
    end)
  end

  defp path_table(%{requests: %{by_path: by_path}}) when map_size(by_path) == 0 do
    ~s|<p class="text-subtle" data-testid="stats-empty">No requests recorded yet.</p>|
  end

  defp path_table(%{requests: %{by_path: by_path}}) do
    rows =
      by_path
      |> Enum.sort_by(fn {_path, stats} -> stats.count end, :desc)
      |> Enum.map_join("\n", &path_row/1)

    """
    <div class="stat-table-wrap">
      <table class="stat-table" data-testid="stats-path-table">
        <thead>
          <tr>
            <th scope="col">Path</th>
            <th scope="col">Count</th>
            <th scope="col">Status</th>
            <th scope="col">Mean</th>
            <th scope="col">Median</th>
            <th scope="col">p95</th>
            <th scope="col">Max</th>
          </tr>
        </thead>
        <tbody>#{rows}</tbody>
      </table>
    </div>
    """
  end

  defp path_row({path, stats}) do
    """
    <tr>
      <th scope="row"><a href="#{esc(path)}">#{esc(path)}</a></th>
      <td>#{format_int(stats.count)}</td>
      <td>#{status_cell(stats.status)}</td>
      <td>#{ms(stats.all_time_mean_ms)}</td>
      <td>#{ms(stats.window.median_ms)}</td>
      <td>#{ms(stats.window.p95_ms)}</td>
      <td>#{ms(stats.window.max_ms)}</td>
    </tr>
    """
  end

  defp status_cell(status) when map_size(status) == 0, do: "—"

  defp status_cell(status) do
    status
    |> Enum.sort()
    |> Enum.map_join(" ", fn {class, count} ->
      ~s|<span class="stat-status stat-status--#{esc(String.first(class))}">#{esc(class)} #{format_int(count)}</span>|
    end)
  end

  defp ms(nil), do: "—"
  defp ms(value), do: "#{value} ms"

  defp format_rate(nil), do: "—"
  defp format_rate(rate), do: "#{Float.round(rate * 100, 1)}%"

  defp format_int(nil), do: "—"

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp format_int(n), do: to_string(n)

  defp format_uptime(nil), do: "—"

  defp format_uptime(ms) do
    total_sec = div(ms, 1000)
    days = div(total_sec, 86_400)
    hours = div(rem(total_sec, 86_400), 3600)
    minutes = div(rem(total_sec, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m"
      true -> "#{total_sec}s"
    end
  end

  # Templates treat `{` as a placeholder sigil, so escape it alongside HTML.
  defp esc(value) do
    value
    |> to_string()
    |> Plug.HTML.html_escape()
    |> String.replace("{", "&#123;")
  end
end
