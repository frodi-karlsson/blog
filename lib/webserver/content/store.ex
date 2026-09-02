defmodule Webserver.Content.Store do
  @moduledoc """
  A concurrent cache for parsed templates using ETS for fast reads.

  Reads and cache misses are handled entirely in the calling process: a miss
  reads and parses the page itself and writes the result to ETS. The GenServer
  owns only content *generation* (the blog index, tag pages, partials) and
  background revalidation, both of which benefit from being serialized.

  ## Revalidation counters

    * `revalidations` -- checks that found a changed file and rewrote the content
    * `revalidation_errors` -- checks that found a changed file but failed to read
      or parse it

  A check that finds the mtime unchanged is counted in neither, so the sum of the
  two is "files that changed", not "checks performed".
  """

  use GenServer

  alias Webserver.Content.BlogItemRenderer
  alias Webserver.Content.Builder
  alias Webserver.Content.Config
  alias Webserver.Content.PageEntry
  alias Webserver.Content.TableOwner
  alias Webserver.FrontMatter
  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  require Logger

  @spec start_link({String.t(), non_neg_integer(), module(), boolean()}) :: GenServer.on_start()
  def start_link({template_dir, check_interval, reader, live_reload?}) do
    GenServer.start_link(
      __MODULE__,
      {template_dir, check_interval, reader, live_reload?, __MODULE__},
      name: __MODULE__
    )
  end

  @spec get_page(String.t()) :: {:ok, String.t()} | {:error, any()}
  def get_page(path) when is_binary(path), do: get_page(__MODULE__, path)

  @spec get_page(atom() | pid(), String.t()) ::
          {:ok, String.t()} | {:error, any()}
  def get_page(server, path) do
    table = table_for(server)

    case :ets.lookup(table, {:page, path}) do
      [{_, %PageEntry{} = entry}] ->
        handle_maybe_stale(table, server, path, entry)

      [] ->
        telemetry_execute([:cache, :miss], %{count: 1}, %{path: path})
        safe_update_counter(table, :stats_misses)
        fetch_and_cache(table, path)
    end
  end

  @spec stats(atom() | pid()) :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          revalidations: non_neg_integer(),
          revalidation_errors: non_neg_integer()
        }
  def stats(server \\ __MODULE__) do
    table = table_for(server)

    %{
      hits: get_stat(table, :stats_hits),
      misses: get_stat(table, :stats_misses),
      revalidations: get_stat(table, :stats_revalidations),
      revalidation_errors: get_stat(table, :stats_revalidation_errors)
    }
  end

  @spec force_refresh(atom() | pid()) :: :ok | {:error, term()}
  def force_refresh(server \\ __MODULE__), do: GenServer.call(server, :force_refresh)

  @spec get_partials(atom() | pid()) :: {:ok, map()}
  def get_partials(server \\ __MODULE__) do
    case :ets.lookup(table_for(server), :partials) do
      [{:partials, partials}] -> {:ok, partials}
      _ -> {:ok, %{}}
    end
  end

  @spec get_compiled_partials(atom() | pid()) :: {:ok, map()}
  def get_compiled_partials(server \\ __MODULE__) do
    case :ets.lookup(table_for(server), :compiled_partials) do
      [{:compiled_partials, compiled}] -> {:ok, compiled}
      _ -> {:ok, %{}}
    end
  end

  defp handle_maybe_stale(table, server, path, %PageEntry{} = entry) do
    interval = Config.check_interval(table)
    now = System.system_time(:millisecond)

    stale? = interval == 0 or now - entry.last_checked_at >= interval

    # Generated pages (tags index, per-tag pages) have no file behind them --
    # they are rebuilt by :refresh_content, not by mtime -- so there is nothing
    # for revalidation to check.
    if stale? and entry.mtime != :generated do
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path, status: :stale})
      safe_update_counter(table, :stats_hits)

      # last_checked_at is advanced by the revalidation itself, and only when the
      # check actually completes. Advancing it here would hide a failing page for
      # a full interval.
      if :ets.insert_new(table, {{:revalidate_in_flight, path}, true}) do
        GenServer.cast(server, {:revalidate_async, path, now})
      end

      {:ok, entry.parsed}
    else
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path})
      safe_update_counter(table, :stats_hits)
      {:ok, entry.parsed}
    end
  end

  # Runs in the calling process, so concurrent misses no longer queue behind one
  # another. Two callers missing the same path may both parse it; the writes are
  # idempotent and last-write-wins, and parsing is deterministic given the same
  # inputs, so both produce identical HTML. That is cheaper to reason about than a
  # lock, and a herd on a cold path is rare.
  defp fetch_and_cache(table, path) do
    config = Config.get(table)
    {:ok, partials} = get_partials(table)
    {:ok, compiled} = get_compiled_partials(table)

    with {:ok, content} <- config.reader.read_page(config.template_dir, path),
         {meta, body} = FrontMatter.parse(content),
         {:ok, parsed} <-
           parse_page(body, meta, config.template_dir, partials, compiled) do
      entry = %PageEntry{
        parsed: parsed,
        mtime: config.reader.file_mtime(config.template_dir, "pages/#{path}"),
        last_checked_at: System.system_time(:millisecond)
      }

      :ets.insert(table, {{:page, path}, entry})
      {:ok, parsed}
    end
  end

  @impl true
  def init({template_dir, check_interval, reader, live_reload?, table}) do
    TableOwner.ensure_table(table)

    # Revalidation in-flight markers are transient. The table now outlives this
    # process, so a crash mid-revalidation would otherwise leave a marker behind
    # forever, permanently disabling background revalidation for that page.
    :ets.match_delete(table, {{:revalidate_in_flight, :_}, :_})

    Config.put(table, %{
      template_dir: template_dir,
      check_interval: check_interval,
      reader: reader,
      live_reload?: live_reload?
    })

    :ets.insert(table, {:stats_hits, 0})
    :ets.insert(table, {:stats_misses, 0})
    :ets.insert(table, {:stats_revalidations, 0})
    :ets.insert(table, {:stats_revalidation_errors, 0})

    Logger.info(%{event: "cache_initializing", template_dir: template_dir, reader: reader})

    state = %{
      table: table,
      template_dir: template_dir,
      check_interval: check_interval,
      reader: reader,
      live_reload?: live_reload?,
      partials: %{}
    }

    case load_and_generate_all(state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:invalidate, filename}, state) do
    :ets.delete(state.table, {:page, filename})
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_content, state) do
    {:noreply, do_generate_content(state)}
  end

  @impl true
  def handle_cast({:revalidate_async, path, checked_at}, state) do
    case :ets.lookup(state.table, {:page, path}) do
      [{_, %PageEntry{} = current_entry}] ->
        if current_entry.last_checked_at > checked_at do
          {:noreply, state}
        else
          do_revalidate_async(path, current_entry, checked_at, state)
        end

      _ ->
        {:noreply, state}
    end
  after
    :ets.delete(state.table, {:revalidate_in_flight, path})
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, stats(state.table), state}
  end

  @impl true
  def handle_call(:force_refresh, _from, state) do
    :ets.match_delete(state.table, {{:page, :_}, :_})
    :ets.insert(state.table, {:stats_hits, 0})
    :ets.insert(state.table, {:stats_misses, 0})
    :ets.insert(state.table, {:stats_revalidations, 0})
    :ets.insert(state.table, {:stats_revalidation_errors, 0})

    case load_and_generate_all(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Safety net only: handle_maybe_stale/4 no longer schedules generated pages,
  # but a cast issued before a deploy can still be sitting in the mailbox.
  defp do_revalidate_async(_path, %PageEntry{mtime: :generated}, _checked_at, state) do
    {:noreply, state}
  end

  defp do_revalidate_async(path, %PageEntry{} = entry, checked_at, state) do
    new_mtime = mtime_for_file(state, "pages/#{path}")

    if new_mtime == entry.mtime do
      # The check completed and found nothing to do. That is still a completed
      # check, so the timestamp advances -- otherwise nothing ever would for an
      # unchanged page, and every later request would cast again.
      :ets.insert(state.table, {{:page, path}, %PageEntry{entry | last_checked_at: checked_at}})
    else
      revalidate_changed_file(path, new_mtime, checked_at, state)
    end

    {:noreply, state}
  end

  defp revalidate_changed_file(path, new_mtime, checked_at, state) do
    {:ok, compiled} = get_compiled_partials(state.table)

    with {:ok, content} <- state.reader.read_page(state.template_dir, path),
         {meta, body} = FrontMatter.parse(content),
         {:ok, parsed} <-
           parse_page(body, meta, state.template_dir, state.partials, compiled) do
      telemetry_execute([:cache, :revalidate], %{count: 1}, %{path: path, reason: :mtime_changed})
      safe_update_counter(state.table, :stats_revalidations)

      new_entry = %PageEntry{parsed: parsed, mtime: new_mtime, last_checked_at: checked_at}
      :ets.insert(state.table, {{:page, path}, new_entry})
    else
      {:error, reason} -> revalidate_failed(path, reason, state)
      other -> revalidate_failed(path, other, state)
    end
  end

  # No ETS write, deliberately: not advancing last_checked_at means the page is
  # retried on the next request, instead of serving stale content for a full
  # interval with nothing but a counter to show for it.
  #
  # The consequence, accepted knowingly: a persistently broken page is re-read
  # and re-parsed once per request, not once per interval. The in-flight marker
  # bounds that to one attempt at a time so it cannot pile up, and requests keep
  # returning the cached content immediately, so the cost is background work
  # rather than latency. In exchange, a fixed page heals on the very next
  # request instead of up to an interval later. Interval-spaced retry would need
  # a separate last_failed_at field or a backoff; not worth it at this size.
  defp revalidate_failed(path, reason, state) do
    safe_update_counter(state.table, :stats_revalidation_errors)
    Logger.warning(%{event: "page_revalidate_failed", path: path, reason: reason})
  end

  defp load_and_generate_all(state) do
    case state.reader.get_partials(state.template_dir) do
      {:ok, partials} ->
        {:ok, do_generate_content(%{state | partials: partials})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_generate_content(state) do
    %{rows: rows, partials: partials, tag_page_filenames: filenames} = Builder.build(state)

    # Prune and insert touch disjoint key sets — the prune deletes only
    # `previous - filenames`, the rows write only `filenames` — so the order of
    # these two lines does not matter.
    prune_stale_tag_pages(state.table, filenames)
    Enum.each(rows, &:ets.insert(state.table, &1))
    :ets.insert(state.table, {:generated_tag_pages, filenames})

    # Any page cached against a previous partials generation is now wrong, and its
    # file mtime is unchanged so revalidation would never correct it. Generated
    # pages were just written above, so only file-backed entries are dropped.
    evict_file_backed_pages(state.table)

    %{state | partials: partials}
  end

  # Narrows, but does not close, the window: cache misses read the `:partials`
  # row in the calling process, so a caller that read the old row and parsed
  # against it can still insert *after* this eviction and land a stale entry.
  # What remains is a single ETS insert wide rather than a full disk re-read plus
  # regeneration. Closing it properly means stamping each PageEntry with the
  # partials generation it parsed against and evicting stale stamps; that is a
  # bigger change than this one.
  #
  # Filtered in Elixir rather than by match spec on purpose: ETS match specs
  # cannot pattern-match inside a struct, so `entry.mtime != :generated` is not
  # expressible as a guard here.
  defp evict_file_backed_pages(table) do
    table
    |> :ets.select([{{{:page, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.each(fn {path, entry} ->
      if entry.mtime != :generated, do: :ets.delete(table, {:page, path})
    end)
  end

  defp prune_stale_tag_pages(table, current_filenames) do
    previous =
      case :ets.lookup(table, :generated_tag_pages) do
        [{:generated_tag_pages, set}] -> set
        [] -> MapSet.new()
      end

    previous
    |> MapSet.difference(current_filenames)
    |> Enum.each(&:ets.delete(table, {:page, &1}))
  end

  # The single parse entry point. The GenServer revalidation path passes its own
  # state's template_dir/partials; a caller-side miss passes the config and the
  # published `:partials` row. Taking the two values explicitly, rather than a
  # state map, is what lets both share this.
  defp parse_page(body, meta, template_dir, partials, compiled_partials) do
    Parser.parse(%ParseInput{
      file: body,
      template_dir: template_dir,
      partials: partials,
      compiled_partials: compiled_partials,
      metadata: enrich_metadata(meta, partials)
    })
  end

  defp enrich_metadata(meta, partials) do
    tags = FrontMatter.parse_tags(meta["tags"])
    Map.put(meta, "tags", BlogItemRenderer.render_tag_chips(tags, partials))
  end

  defp mtime_for_file(state, relative_path) do
    state.reader.file_mtime(state.template_dir, relative_path)
  end

  defp table_for(server) when is_atom(server), do: server

  defp table_for(server) when is_pid(server) do
    case Process.info(server, :registered_name) do
      {:registered_name, name} -> name
      _ -> raise "ETS-backed Store requires a named process"
    end
  end

  defp get_stat(table, key) do
    case :ets.lookup(table, key) do
      [{^key, val}] -> val
      _ -> 0
    end
  end

  defp safe_update_counter(table, key) do
    :ets.update_counter(table, key, {2, 1}, {key, 0})
  end

  defp telemetry_execute(event_path, measurements, metadata) do
    :telemetry.execute([:webserver] ++ event_path, measurements, metadata)
  end
end
