defmodule Webserver.TemplateServer.Cache do
  @moduledoc """
  GenServer that caches parsed templates with TTL-based mtime revalidation.

  Cache entries are revalidated at most once per `check_interval` milliseconds.
  Set `check_interval` to `0` to always check mtimes (dev/test), or a higher
  value for production (default: 60 seconds).
  """

  use GenServer

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  require Logger

  defmodule State do
    @moduledoc "Internal state for the Cache GenServer."
    defstruct [:base_url, :check_interval, :reader, :partials, :pages, :stats, :last_check_at]
  end

  defmodule PartialEntry do
    @moduledoc "Cached entry for a partial file."
    defstruct [:content, :mtime]
    def new(content, mtime), do: %__MODULE__{content: content, mtime: mtime}
  end

  defmodule PageEntry do
    @moduledoc "Cached entry for a parsed page."
    defstruct [:parsed, :mtime]
    def new(parsed, mtime), do: %__MODULE__{parsed: parsed, mtime: mtime}
  end

  defmodule Stats do
    @moduledoc "Cache hit/miss/revalidation statistics."
    defstruct hits: 0, misses: 0, revalidations: 0

    def new, do: %__MODULE__{}
    def increment(%__MODULE__{} = s, :hits), do: %{s | hits: s.hits + 1}
    def increment(%__MODULE__{} = s, :misses), do: %{s | misses: s.misses + 1}

    def increment(%__MODULE__{} = s, :revalidations),
      do: %{s | revalidations: s.revalidations + 1}
  end

  @spec start_link({String.t(), non_neg_integer(), module()}) :: GenServer.on_start()
  def start_link({base_url, check_interval, reader}) do
    GenServer.start_link(__MODULE__, {base_url, check_interval, reader}, name: __MODULE__)
  end

  @spec get_page(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def get_page(path), do: GenServer.call(__MODULE__, {:get_page, path})

  @spec stats() :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          revalidations: non_neg_integer()
        }
  def stats, do: GenServer.call(__MODULE__, :stats)

  @spec force_refresh() :: :ok | {:error, term()}
  def force_refresh, do: GenServer.call(__MODULE__, :force_refresh)

  @impl true
  def init({base_url, check_interval, reader})
      when is_binary(base_url) and is_integer(check_interval) and is_atom(reader) do
    Logger.info(%{event: "cache_initializing", base_url: base_url, reader: reader})

    case reader.get_partials(base_url) do
      {:ok, partials} ->
        Logger.info(%{
          event: "cache_initialized",
          base_url: base_url,
          partial_count: map_size(partials)
        })

        state = %State{
          base_url: base_url,
          check_interval: check_interval,
          reader: reader,
          partials: %{},
          pages: %{},
          stats: Stats.new(),
          last_check_at: 0
        }

        state =
          Enum.reduce(partials, state, fn {key, content}, acc ->
            mtime = mtime_for_file(base_url, Path.join("partials", Path.basename(key)))
            put_in(acc.partials[key], PartialEntry.new(content, mtime))
          end)

        {:ok, state}

      {:error, reason} ->
        Logger.error(%{event: "cache_init_failed", base_url: base_url, reason: reason})
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get_page, path}, _from, state) do
    cache_key = "pages/#{path}"
    now = System.system_time(:millisecond)
    partials = build_partials_map(state.partials)

    case Map.fetch(state.pages, cache_key) do
      {:ok, %PageEntry{parsed: parsed, mtime: cached_mtime}} ->
        handle_cached_page(path, cache_key, parsed, cached_mtime, state, partials, now)

      :error ->
        handle_cache_miss(path, cache_key, state, partials, now)
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats_map = %{
      hits: state.stats.hits,
      misses: state.stats.misses,
      revalidations: state.stats.revalidations
    }

    {:reply, stats_map, state}
  end

  @impl true
  def handle_call(:force_refresh, _from, state) do
    Logger.info(%{event: "cache_force_refresh"})

    case state.reader.get_partials(state.base_url) do
      {:ok, partials} ->
        new_partials =
          Enum.reduce(partials, %{}, fn {key, content}, acc ->
            mtime = mtime_for_file(state.base_url, Path.join("partials", Path.basename(key)))
            Map.put(acc, key, PartialEntry.new(content, mtime))
          end)

        new_state = %{
          state
          | partials: new_partials,
            pages: %{},
            stats: Stats.new(),
            last_check_at: 0
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error(%{event: "cache_refresh_failed", reason: reason})
        {:reply, {:error, reason}, state}
    end
  end

  defp handle_cached_page(path, cache_key, parsed, cached_mtime, state, partials, now) do
    should_revalidate = now - state.last_check_at >= state.check_interval

    if should_revalidate and mtime_changed?(state.base_url, cache_key, cached_mtime) do
      Logger.debug(%{event: "page_revalidation", path: path})

      case state.reader.read_page(state.base_url, path) do
        {:ok, content} -> revalidate_page(cache_key, content, state, partials, now)
        {:error, _} -> record_miss(state, now)
      end
    else
      Logger.debug(%{event: "cache_hit", path: path})
      record_hit(parsed, state)
    end
  end

  defp handle_cache_miss(path, cache_key, state, partials, now) do
    Logger.debug(%{event: "cache_miss", path: path})

    case state.reader.read_page(state.base_url, path) do
      {:ok, content} -> cache_new_page(cache_key, content, state, partials, now)
      {:error, _} -> record_miss(state, now)
    end
  end

  defp revalidate_page(cache_key, content, state, partials, now) do
    case parse_page(content, partials, state.base_url) do
      {:ok, new_parsed} ->
        current_mtime = mtime_for_file(state.base_url, cache_key)
        new_pages = Map.put(state.pages, cache_key, PageEntry.new(new_parsed, current_mtime))
        new_stats = Stats.increment(state.stats, :revalidations)

        {:reply, {:ok, new_parsed},
         %{state | pages: new_pages, stats: new_stats, last_check_at: now}}

      {:error, _} ->
        record_miss(state, now)
    end
  end

  defp cache_new_page(cache_key, content, state, partials, now) do
    case parse_page(content, partials, state.base_url) do
      {:ok, parsed} ->
        mtime = mtime_for_file(state.base_url, cache_key)
        new_pages = Map.put(state.pages, cache_key, PageEntry.new(parsed, mtime))
        new_stats = Stats.increment(state.stats, :misses)
        {:reply, {:ok, parsed}, %{state | pages: new_pages, stats: new_stats, last_check_at: now}}

      {:error, _} ->
        record_miss(state, now)
    end
  end

  defp record_hit(parsed, state) do
    {:reply, {:ok, parsed}, %{state | stats: Stats.increment(state.stats, :hits)}}
  end

  defp record_miss(state, now) do
    {:reply, {:error, :not_found},
     %{state | stats: Stats.increment(state.stats, :misses), last_check_at: now}}
  end

  defp build_partials_map(partials) do
    Map.new(partials, fn {k, %PartialEntry{content: content}} -> {k, content} end)
  end

  defp mtime_changed?(base_url, cache_key, cached_mtime) do
    mtime_for_file(base_url, cache_key) != cached_mtime
  end

  defp parse_page(content, partials, base_url) do
    Parser.parse(%ParseInput{file: content, base_url: base_url, partials: partials})
  end

  defp mtime_for_file(base_url, relative_path) do
    case File.stat(Path.join([base_url, relative_path])) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end
end
