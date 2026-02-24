defmodule TemplateServer.Cache do
  @moduledoc """
  Singleton GenServer that caches templates with mtime-based invalidation.

  Cache Structure:
  %{
    base_url: "/priv/templates",
    partials: %{"partials/head.html" => {content, mtime}},
    pages: %{"pages/index.html" => {parsed, mtime}},
    stats: %{hits: 0, misses: 0, mtime_checks: 0, revalidations: 0}
  }
  """

  use GenServer
  require Logger

  defstruct [:base_url, :partials, :pages, :stats]

  @spec start_link(binary()) :: GenServer.on_start()
  def start_link(base_url) do
    GenServer.start_link(__MODULE__, base_url, name: __MODULE__)
  end

  @spec get_partials(pid()) :: map()
  def get_partials(pid \\ __MODULE__) do
    GenServer.call(pid, {:get_partials})
  end

  @spec get_page(pid(), binary()) :: {:ok, binary()} | {:error, :not_found}
  def get_page(pid \\ __MODULE__, path) do
    GenServer.call(pid, {:get_page, path})
  end

  @spec stats(pid()) :: map()
  def stats(pid \\ __MODULE__) do
    GenServer.call(pid, {:stats})
  end

  @spec force_refresh(pid()) :: :ok | {:error, term()}
  def force_refresh(pid \\ __MODULE__) do
    GenServer.call(pid, {:force_refresh})
  end

  @impl true
  def init(base_url) when is_binary(base_url) do
    Logger.info(%{event: "cache_initializing", base_url: base_url})

    case TemplateServer.TemplateReader.get_partials(base_url) do
      {:ok, partials} ->
        Logger.info(%{
          event: "cache_initialized",
          base_url: base_url,
          partial_count: map_size(partials)
        })

        state = %__MODULE__{
          base_url: base_url,
          partials: %{},
          pages: %{},
          stats: %{hits: 0, misses: 0, mtime_checks: 0, revalidations: 0}
        }

        state =
          Enum.reduce(partials, state, fn {key, content}, acc ->
            mtime = mtime_for_file(base_url, Path.join("partials", Path.basename(key)))
            put_in(acc.partials[key], {content, mtime})
          end)

        {:ok, state}

      {:error, reason} ->
        Logger.error(%{event: "cache_init_failed", base_url: base_url, reason: reason})
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get_partials}, _from, state) do
    updated_state = increment_stats(state, :mtime_checks)

    updated_partials =
      Enum.reduce(state.partials, updated_state.partials, fn
        {key, {_content, cached_mtime}}, acc ->
          case mtime_for_file(state.base_url, Path.join("partials", Path.basename(key))) do
            ^cached_mtime ->
              acc

            new_mtime ->
              Logger.debug(%{event: "partial_revalidation", key: key})

              case TemplateServer.TemplateReader.read_partial(state.base_url, Path.basename(key)) do
                {:ok, new_content} ->
                  Map.put(acc, key, {new_content, new_mtime})

                {:error, _} ->
                  Logger.warning("partial_reload_failed", key: key)
                  acc
              end
          end
      end)

    new_state = %{
      updated_state
      | partials: updated_partials,
        stats: increment(updated_state.stats, :hits)
    }

    partials_content = Map.new(updated_partials, fn {k, {content, _mtime}} -> {k, content} end)
    {:reply, partials_content, new_state}
  end

  @impl true
  def handle_call({:get_page, path}, _from, state) do
    updated_state = increment_stats(state, :mtime_checks)
    cache_key = "pages/#{path}"

    partials_content =
      Map.new(updated_state.partials, fn {k, {content, _mtime}} -> {k, content} end)

    case Map.fetch(updated_state.pages, cache_key) do
      {:ok, {_parsed, cached_mtime}} ->
        current_mtime = mtime_for_file(state.base_url, cache_key)

        if current_mtime == cached_mtime do
          Logger.debug(%{event: "cache_hit", path: path})
          new_state = %{updated_state | stats: increment(updated_state.stats, :hits)}
          {:reply, {:ok, elem(Map.get(updated_state.pages, cache_key), 0)}, new_state}
        else
          Logger.debug(%{event: "page_revalidation", path: cache_key})
          Logger.debug(%{event: "page_mtime_changed", path: cache_key})
          Logger.debug(%{event: "cache_revalidation", path: path})

          case TemplateServer.TemplateReader.read_page(state.base_url, path) do
            {:ok, content} ->
              case parse_page(content, partials_content, state.base_url) do
                {:ok, parsed} ->
                  new_page = {parsed, current_mtime}
                  new_pages = Map.put(updated_state.pages, cache_key, new_page)
                  new_stats = increment(updated_state.stats, :revalidations)
                  {:reply, {:ok, parsed}, %{updated_state | pages: new_pages, stats: new_stats}}

                {:error, _reason} ->
                  new_state = %{updated_state | stats: increment(updated_state.stats, :misses)}
                  {:reply, {:error, :not_found}, new_state}
              end

            {:error, _} ->
              new_state = %{updated_state | stats: increment(updated_state.stats, :misses)}
              {:reply, {:error, :not_found}, new_state}
          end
        end

      :error ->
        Logger.debug(%{event: "cache_miss", path: path})

        case TemplateServer.TemplateReader.read_page(state.base_url, path) do
          {:ok, content} ->
            case parse_page(content, partials_content, state.base_url) do
              {:ok, parsed} ->
                mtime = mtime_for_file(state.base_url, cache_key)
                new_page = {parsed, mtime}
                new_pages = Map.put(updated_state.pages, cache_key, new_page)

                new_state = %{
                  updated_state
                  | pages: new_pages,
                    stats: increment(updated_state.stats, :misses)
                }

                {:reply, {:ok, parsed}, new_state}

              {:error, _reason} ->
                new_state = %{updated_state | stats: increment(updated_state.stats, :misses)}
                {:reply, {:error, :not_found}, new_state}
            end

          {:error, _} ->
            new_state = %{updated_state | stats: increment(updated_state.stats, :misses)}
            {:reply, {:error, :not_found}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:stats}, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_call({:force_refresh}, _from, state) do
    Logger.info(%{event: "cache_force_refresh"})

    case TemplateServer.TemplateReader.get_partials(state.base_url) do
      {:ok, partials} ->
        new_partials =
          Enum.reduce(partials, %{}, fn {key, content}, acc ->
            mtime = mtime_for_file(state.base_url, Path.join("partials", Path.basename(key)))
            Map.put(acc, key, {content, mtime})
          end)

        new_state = %{
          state
          | partials: new_partials,
            pages: %{},
            stats: %{hits: 0, misses: 0, mtime_checks: 0, revalidations: 0}
        }

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error(%{event: "cache_refresh_failed", reason: reason})
        {:reply, {:error, reason}, state}
    end
  end

  defp parse_page(content, partials, base_url) do
    Parser.parse(%Parser.ParseInput{
      file: content,
      base_url: base_url,
      partials: partials
    })
  end

  defp mtime_for_file(base_url, relative_path) do
    full_path = Path.join([base_url, relative_path])

    case File.stat(full_path) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp increment(stats, key) do
    Map.update(stats, key, 1, &(&1 + 1))
  end

  defp increment_stats(state, key) do
    %{state | stats: increment(state.stats, key)}
  end
end
