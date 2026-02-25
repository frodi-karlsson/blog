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
  def start_link({template_dir, check_interval, reader}) do
    GenServer.start_link(__MODULE__, {template_dir, check_interval, reader, __MODULE__},
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
        GenServer.call(server, {:fetch_and_cache, path})
    end
  end

  @spec stats(atom() | pid()) :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          revalidations: non_neg_integer()
        }
  def stats(server \\ __MODULE__) do
    table = table_for(server)

    %{
      hits: get_stat(table, :stats_hits),
      misses: get_stat(table, :stats_misses),
      revalidations: get_stat(table, :stats_revalidations)
    }
  end

  @spec get_sitemap(atom() | pid()) :: [map()]
  def get_sitemap(server \\ __MODULE__) do
    table = table_for(server)

    case :ets.lookup(table, :page_registry) do
      [{_, pages}] -> Enum.reject(pages, &Map.get(&1, "noindex", false))
      _ -> []
    end
  end

  @spec force_refresh(atom() | pid()) :: :ok | {:error, term()}
  def force_refresh(server \\ __MODULE__), do: GenServer.call(server, :force_refresh)

  defp handle_maybe_stale(table, server, path, entry) do
    [{:config, {_template_dir, interval, _reader}}] = :ets.lookup(table, :config)
    now = System.system_time(:millisecond)

    if interval == 0 or now - entry.last_checked_at >= interval do
      GenServer.call(server, {:revalidate, path, entry, now})
    else
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path})
      safe_update_counter(table, :stats_hits)
      {:ok, entry.parsed}
    end
  end

  @impl true
  def init({template_dir, check_interval, reader, table}) do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: :auto
    ])

    :ets.insert(table, {:config, {template_dir, check_interval, reader}})
    :ets.insert(table, {:stats_hits, 0})
    :ets.insert(table, {:stats_misses, 0})
    :ets.insert(table, {:stats_revalidations, 0})

    Logger.info(%{event: "cache_initializing", template_dir: template_dir, reader: reader})

    case reader.get_partials(template_dir) do
      {:ok, partials} ->
        Enum.each(partials, fn {key, content} ->
          :ets.insert(table, {{:partial, key}, content})
        end)

        state = %{
          table: table,
          template_dir: template_dir,
          check_interval: check_interval,
          reader: reader
        }

        generate_livereload_partial(state)
        generate_blog_index(state)
        generate_page_registry(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:invalidate, filename}, state) do
    :ets.delete(state.table, {:page, filename})
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_blog_index, state) do
    generate_blog_index(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_page_registry, state) do
    generate_page_registry(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:fetch_and_cache, path}, _from, state) do
    case :ets.lookup(state.table, {:page, path}) do
      [{_, %PageEntry{parsed: parsed}}] ->
        safe_update_counter(state.table, :stats_hits)
        {:reply, {:ok, parsed}, state}

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
      safe_update_counter(state.table, :stats_hits)
      {:reply, {:ok, current_entry.parsed}, state}
    else
      do_revalidate(path, entry, now, state)
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, stats(state.table), state}
  end

  @impl true
  def handle_call(:force_refresh, _from, state) do
    case state.reader.get_partials(state.template_dir) do
      {:ok, partials} ->
        :ets.match_delete(state.table, {{:page, :_}, :_})
        :ets.insert(state.table, {:stats_hits, 0})
        :ets.insert(state.table, {:stats_misses, 0})
        :ets.insert(state.table, {:stats_revalidations, 0})

        Enum.each(partials, fn {key, content} ->
          :ets.insert(state.table, {{:partial, key}, content})
        end)

        generate_livereload_partial(state)
        generate_blog_index(state)
        generate_page_registry(state)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_fetch_and_cache(path, state) do
    now = System.system_time(:millisecond)

    case state.reader.read_page(state.template_dir, path) do
      {:ok, content} ->
        case parse_page(content, state) do
          {:ok, parsed} ->
            mtime = mtime_for_file(state, "pages/#{path}")
            entry = %PageEntry{parsed: parsed, mtime: mtime, last_checked_at: now}
            :ets.insert(state.table, {{:page, path}, entry})
            {:reply, {:ok, parsed}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_revalidate(path, entry, now, state) do
    new_mtime = mtime_for_file(state, "pages/#{path}")

    if new_mtime != entry.mtime do
      perform_revalidation(path, new_mtime, now, state)
    else
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path, status: :revalidated})
      safe_update_counter(state.table, :stats_hits)
      new_entry = %{entry | last_checked_at: now}
      :ets.insert(state.table, {{:page, path}, new_entry})
      {:reply, {:ok, entry.parsed}, state}
    end
  end

  defp perform_revalidation(path, new_mtime, now, state) do
    telemetry_execute([:cache, :revalidate], %{count: 1}, %{
      path: path,
      reason: :mtime_changed
    })

    safe_update_counter(state.table, :stats_revalidations)

    case state.reader.read_page(state.template_dir, path) do
      {:ok, content} ->
        case parse_page(content, state) do
          {:ok, parsed} ->
            new_entry = %PageEntry{parsed: parsed, mtime: new_mtime, last_checked_at: now}
            :ets.insert(state.table, {{:page, path}, new_entry})
            {:reply, {:ok, parsed}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      _ ->
        :ets.delete(state.table, {:page, path})
        {:reply, {:error, :not_found}, state}
    end
  end

  defp generate_livereload_partial(state) do
    script =
      if Application.get_env(:webserver, :live_reload) do
        ~S|<script src="/static/js/livereload.js"></script>|
      else
        ""
      end

    :ets.insert(state.table, {{:partial, "partials/generated_livereload_script.html"}, script})
  end

  defp generate_blog_index(state) do
    partial_key = "partials/generated_blog_items.html"

    rendered_items =
      case state.reader.read_manifest(state.template_dir) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, posts} ->
              Enum.map_join(posts, "\n", &render_blog_item_if_exists(&1, state))

            {:error, reason} ->
              Logger.warning(%{event: "blog_manifest_decode_failed", reason: reason})
              ""
          end

        _ ->
          ""
      end

    :ets.insert(state.table, {{:partial, partial_key}, rendered_items})
  end

  defp generate_page_registry(state) do
    pages =
      case state.reader.read_pages_manifest(state.template_dir) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, decoded} ->
              decoded

            {:error, reason} ->
              Logger.warning(%{event: "pages_manifest_decode_failed", reason: reason})
              []
          end

        _ ->
          []
      end

    valid_pages = Enum.filter(pages, &page_exists?(&1, state))
    :ets.insert(state.table, {:page_registry, valid_pages})
  end

  defp page_exists?(%{"id" => id}, state) do
    case state.reader.read_page(state.template_dir, "#{id}.html") do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp render_blog_item_if_exists(%{"id" => id} = post, state) do
    case state.reader.read_page(state.template_dir, "#{id}.html") do
      {:ok, _} -> render_blog_item(post, state)
      _ -> ""
    end
  end

  defp render_blog_item(post, state) do
    template = """
    <% blog_index_item.html %>
    <slot:category>#{escape(post["category"])}</slot:category>
    <slot:date>#{escape(post["date"])}</slot:date>
    <slot:url>#{escape("/#{post["id"]}")}</slot:url>
    <slot:title>#{escape(post["title"])}</slot:title>
    <slot:summary>#{escape(post["summary"])}</slot:summary>
    <%/ blog_index_item.html %>
    """

    case parse_page(template, state) do
      {:ok, html} -> html
      _ -> ""
    end
  end

  defp escape(nil), do: ""
  defp escape(value), do: Plug.HTML.html_escape(value)

  defp parse_page(content, state) do
    partials =
      state.table
      |> :ets.match({{:partial, :"$1"}, :"$2"})
      |> Map.new(fn [k, v] -> {k, v} end)

    Parser.parse(%ParseInput{file: content, template_dir: state.template_dir, partials: partials})
  end

  defp mtime_for_file(state, relative_path) do
    state.reader.file_mtime(state.template_dir, relative_path)
  end

  defp table_for(server) when is_atom(server), do: server

  defp table_for(server) when is_pid(server) do
    case Process.info(server, :registered_name) do
      {:registered_name, name} -> name
      _ -> raise "ETS-backed Cache requires a named process"
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
