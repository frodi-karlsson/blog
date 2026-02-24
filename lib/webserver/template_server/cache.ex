defmodule Webserver.TemplateServer.Cache do
  @moduledoc """
  A concurrent cache for parsed templates using ETS for fast reads and a GenServer
  for serialized writes and revalidations.
  """

  use GenServer

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  require Logger

  defmodule PageEntry do
    @moduledoc false
    defstruct [:parsed, :mtime, :last_checked_at]
  end

  @spec start_link({String.t(), non_neg_integer(), module()}) :: GenServer.on_start()
  def start_link({base_url, check_interval, reader}) do
    GenServer.start_link(__MODULE__, {base_url, check_interval, reader, __MODULE__},
      name: __MODULE__
    )
  end

  @spec get_page(String.t()) :: {:ok, String.t()} | {:error, atom() | {atom(), any()}}
  def get_page(path) when is_binary(path), do: get_page(__MODULE__, path)

  @spec get_page(atom() | pid(), String.t()) ::
          {:ok, String.t()} | {:error, atom() | {atom(), any()}}
  def get_page(server, path) do
    table = table_for(server)

    case :ets.lookup(table, {:page, path}) do
      [{_, %PageEntry{} = entry}] ->
        handle_maybe_stale(table, server, path, entry)

      [] ->
        telemetry_execute([:cache, :miss], %{count: 1}, %{path: path})
        GenServer.call(server, {:fetch_and_cache, path})
    end
  end

  @spec stats(atom() | pid()) :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          revalidations: non_neg_integer()
        }
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @spec force_refresh(atom() | pid()) :: :ok | {:error, term()}
  def force_refresh(server \\ __MODULE__), do: GenServer.call(server, :force_refresh)

  defp handle_maybe_stale(table, server, path, entry) do
    [{:config, {_base_url, interval, _reader}}] = :ets.lookup(table, :config)
    now = System.system_time(:millisecond)

    if now - entry.last_checked_at >= interval do
      GenServer.call(server, {:revalidate, path, entry, now})
    else
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path})
      {:ok, entry.parsed}
    end
  end

  @impl true
  def init({base_url, check_interval, reader, table}) do
    :ets.new(table, [:set, :protected, :named_table, read_concurrency: true])
    :ets.insert(table, {:config, {base_url, check_interval, reader}})

    Logger.info(%{event: "cache_initializing", base_url: base_url, reader: reader})

    case reader.get_partials(base_url) do
      {:ok, partials} ->
        Enum.each(partials, fn {key, content} ->
          :ets.insert(table, {{:partial, key}, content})
        end)

        {:ok,
         %{
           table: table,
           base_url: base_url,
           check_interval: check_interval,
           reader: reader,
           hits: 0,
           misses: 0,
           revalidations: 0
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:fetch_and_cache, path}, _from, state) do
    case :ets.lookup(state.table, {:page, path}) do
      [{_, %PageEntry{parsed: parsed}}] ->
        {:reply, {:ok, parsed}, %{state | hits: state.hits + 1}}

      [] ->
        do_fetch_and_cache(path, state)
    end
  end

  @impl true
  def handle_call({:revalidate, path, entry, now}, _from, state) do
    current_entry =
      case :ets.lookup(state.table, {:page, path}) do
        [{_, e}] -> e
        _ -> entry
      end

    if current_entry.last_checked_at > entry.last_checked_at do
      {:reply, {:ok, current_entry.parsed}, %{state | hits: state.hits + 1}}
    else
      do_revalidate(path, entry, now, state)
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       hits: state.hits,
       misses: state.misses,
       revalidations: state.revalidations
     }, state}
  end

  @impl true
  def handle_call(:force_refresh, _from, state) do
    case state.reader.get_partials(state.base_url) do
      {:ok, partials} ->
        :ets.match_delete(state.table, {{:page, :_}, :_})

        Enum.each(partials, fn {key, content} ->
          :ets.insert(state.table, {{:partial, key}, content})
        end)

        {:reply, :ok, %{state | hits: 0, misses: 0, revalidations: 0}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_fetch_and_cache(path, state) do
    now = System.system_time(:millisecond)

    case state.reader.read_page(state.base_url, path) do
      {:ok, content} ->
        case parse_page(content, state) do
          {:ok, parsed} ->
            mtime = mtime_for_file(state.base_url, "pages/#{path}")
            entry = %PageEntry{parsed: parsed, mtime: mtime, last_checked_at: now}
            :ets.insert(state.table, {{:page, path}, entry})
            {:reply, {:ok, parsed}, %{state | misses: state.misses + 1}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} when reason in [:enoent, :invalid_path, :not_found] ->
        {:reply, {:error, :not_found}, %{state | misses: state.misses + 1}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_revalidate(path, entry, now, state) do
    new_mtime = mtime_for_file(state.base_url, "pages/#{path}")

    if new_mtime != entry.mtime do
      perform_revalidation(path, new_mtime, now, state)
    else
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path, status: :revalidated})
      new_entry = %{entry | last_checked_at: now}
      :ets.insert(state.table, {{:page, path}, new_entry})
      {:reply, {:ok, entry.parsed}, %{state | hits: state.hits + 1}}
    end
  end

  defp perform_revalidation(path, new_mtime, now, state) do
    telemetry_execute([:cache, :revalidate], %{count: 1}, %{
      path: path,
      reason: :mtime_changed
    })

    case state.reader.read_page(state.base_url, path) do
      {:ok, content} ->
        case parse_page(content, state) do
          {:ok, parsed} ->
            new_entry = %PageEntry{parsed: parsed, mtime: new_mtime, last_checked_at: now}
            :ets.insert(state.table, {{:page, path}, new_entry})
            {:reply, {:ok, parsed}, %{state | revalidations: state.revalidations + 1}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      _ ->
        :ets.delete(state.table, {:page, path})
        {:reply, {:error, :not_found}, state}
    end
  end

  defp parse_page(content, state) do
    partials =
      state.table
      |> :ets.match({{:partial, :"$1"}, :"$2"})
      |> Map.new(fn [k, v] -> {k, v} end)

    Parser.parse(%ParseInput{file: content, base_url: state.base_url, partials: partials})
  end

  defp mtime_for_file(base_url, relative_path) do
    case File.stat(Path.join([base_url, relative_path])) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp table_for(server) when is_atom(server), do: server

  defp table_for(server) when is_pid(server) do
    case Process.info(server, :registered_name) do
      {:registered_name, name} -> name
      _ -> raise "ETS-backed Cache requires a named process"
    end
  end

  defp telemetry_execute(event_path, measurements, metadata) do
    :telemetry.execute([:webserver] ++ event_path, measurements, metadata)
  end
end
