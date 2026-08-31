defmodule Webserver.TemplateServer.Cache do
  @moduledoc """
  A concurrent cache for parsed templates using ETS for fast reads and a GenServer
  for serialized writes and revalidations.
  """

  use GenServer

  alias Webserver.FrontMatter
  alias Webserver.Parser
  alias Webserver.Parser.ParseInput
  alias Webserver.TemplateServer.BlogItemRenderer
  alias Webserver.TemplateServer.ContentGenerator

  require Logger

  defmodule PageEntry do
    @moduledoc false
    defstruct [:parsed, :mtime, :last_checked_at]
  end

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
        GenServer.call(server, {:fetch_and_cache, path})
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

  @spec list_posts(atom() | pid()) :: [Webserver.TemplateServer.Post.t()]
  def list_posts(server \\ __MODULE__) do
    case :ets.lookup(table_for(server), :posts_db) do
      [{:posts_db, posts}] -> posts
      [] -> []
    end
  end

  @spec posts_by_tag(atom() | pid(), String.t()) :: [Webserver.TemplateServer.Post.t()]
  def posts_by_tag(server \\ __MODULE__, tag) do
    needle = String.downcase(tag)
    Enum.filter(list_posts(server), fn post -> needle in post.tags end)
  end

  @spec search_posts(atom() | pid(), String.t()) :: [Webserver.TemplateServer.Post.t()]
  def search_posts(server \\ __MODULE__, query) do
    q = query |> String.trim() |> String.downcase() |> String.slice(0, 200)

    if q == "" do
      list_posts(server)
    else
      Enum.filter(list_posts(server), fn post ->
        String.contains?(String.downcase(post.title), q) or
          String.contains?(String.downcase(post.summary), q)
      end)
    end
  end

  @spec get_partials(atom() | pid()) :: {:ok, map()}
  def get_partials(server \\ __MODULE__) do
    GenServer.call(server, :get_partials)
  end

  @spec all_tags(atom() | pid()) :: [{String.t(), non_neg_integer()}]
  def all_tags(server \\ __MODULE__) do
    server
    |> list_posts()
    |> Enum.flat_map(& &1.tags)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
  end

  defp handle_maybe_stale(table, server, path, %PageEntry{} = entry) do
    [{:config, {_template_dir, interval, _reader, _live_reload?}}] = :ets.lookup(table, :config)
    now = System.system_time(:millisecond)

    if interval == 0 or now - entry.last_checked_at >= interval do
      telemetry_execute([:cache, :hit], %{count: 1}, %{path: path, status: :stale})
      safe_update_counter(table, :stats_hits)

      new_entry = %PageEntry{entry | last_checked_at: now}
      :ets.insert(table, {{:page, path}, new_entry})

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

  @impl true
  def init({template_dir, check_interval, reader, live_reload?, table}) do
    :ets.new(table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: :auto
    ])

    :ets.insert(table, {:config, {template_dir, check_interval, reader, live_reload?}})
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
    result =
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

    :ets.delete(state.table, {:revalidate_in_flight, path})
    result
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

  def handle_call(:stats, _from, state) do
    {:reply, stats(state.table), state}
  end

  def handle_call(:get_partials, _from, state) do
    {:reply, {:ok, state.partials}, state}
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

  defp do_revalidate_async(_path, %PageEntry{mtime: :generated}, _checked_at, state) do
    {:noreply, state}
  end

  defp do_revalidate_async(path, %PageEntry{} = entry, checked_at, state) do
    new_mtime = mtime_for_file(state, "pages/#{path}")

    if new_mtime != entry.mtime do
      telemetry_execute([:cache, :revalidate], %{count: 1}, %{path: path, reason: :mtime_changed})
      safe_update_counter(state.table, :stats_revalidations)

      with {:ok, content} <- state.reader.read_page(state.template_dir, path),
           {meta, body} <- FrontMatter.parse(content),
           {:ok, parsed} <- parse_page(body, meta, state) do
        new_entry = %PageEntry{parsed: parsed, mtime: new_mtime, last_checked_at: checked_at}
        :ets.insert(state.table, {{:page, path}, new_entry})
      else
        {:error, reason} ->
          safe_update_counter(state.table, :stats_revalidation_errors)
          Logger.warning(%{event: "page_revalidate_failed", path: path, reason: reason})

        other ->
          safe_update_counter(state.table, :stats_revalidation_errors)
          Logger.warning(%{event: "page_revalidate_failed", path: path, reason: other})
      end
    end

    {:noreply, state}
  end

  defp load_and_generate_all(state) do
    case state.reader.get_partials(state.template_dir) do
      {:ok, partials} ->
        Enum.each(partials, fn {key, content} ->
          :ets.insert(state.table, {{:partial, key}, content})
        end)

        state = %{state | partials: partials}

        state =
          state
          |> do_generate_livereload_partial()
          |> do_generate_content()

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_fetch_and_cache(path, state) do
    now = System.system_time(:millisecond)

    case state.reader.read_page(state.template_dir, path) do
      {:ok, content} ->
        {meta, body} = FrontMatter.parse(content)

        case parse_page(body, meta, state) do
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

  defp do_generate_livereload_partial(state) do
    key = "partials/generated_livereload_script.html"
    script = ContentGenerator.generate_livereload_partial(state.live_reload?)
    :ets.insert(state.table, {{:partial, key}, script})
    %{state | partials: Map.put(state.partials, key, script)}
  end

  defp do_generate_content(state) do
    pages_meta = ContentGenerator.scan_pages(state)

    blog_key = "partials/generated_blog_items.html"
    rendered = ContentGenerator.generate_blog_index(pages_meta, state, state.partials)
    :ets.insert(state.table, {{:partial, blog_key}, rendered})

    posts = ContentGenerator.build_posts_db(pages_meta)
    :ets.insert(state.table, {:posts_db, posts})

    partials_with_blog = Map.put(state.partials, blog_key, rendered)

    tags_index_html =
      ContentGenerator.generate_tags_index_page(posts, state, partials_with_blog)

    insert_generated_page(state.table, "tags/index.html", tags_index_html)

    tag_pages = ContentGenerator.generate_tag_pages(posts, state, partials_with_blog)
    refresh_tag_pages(state.table, tag_pages)

    pages = ContentGenerator.generate_page_registry(pages_meta)
    :ets.insert(state.table, {:page_registry, pages})
    :ets.insert(state.table, {:page_path_set, page_path_set(pages)})

    %{state | partials: partials_with_blog}
  end

  # Published alongside the registry so the metrics handler can test a path
  # with a set lookup instead of scanning every page on each request.
  defp page_path_set(pages) do
    pages
    |> Enum.flat_map(fn
      %{"path" => path} when is_binary(path) -> [path]
      _ -> []
    end)
    |> MapSet.new()
  end

  defp refresh_tag_pages(table, tag_pages) do
    new_filenames =
      tag_pages
      |> Map.keys()
      |> Enum.map(&"tags/#{&1}.html")
      |> MapSet.new()

    previous =
      case :ets.lookup(table, :generated_tag_pages) do
        [{:generated_tag_pages, set}] -> set
        [] -> MapSet.new()
      end

    Enum.each(MapSet.difference(previous, new_filenames), fn filename ->
      :ets.delete(table, {:page, filename})
    end)

    Enum.each(tag_pages, fn {tag, html} ->
      insert_generated_page(table, "tags/#{tag}.html", html)
    end)

    :ets.insert(table, {:generated_tag_pages, new_filenames})
  end

  defp insert_generated_page(table, filename, html) do
    entry = %PageEntry{
      parsed: html,
      mtime: :generated,
      last_checked_at: System.system_time(:millisecond)
    }

    :ets.insert(table, {{:page, filename}, entry})
  end

  defp parse_page(content, meta, state) do
    Parser.parse(%ParseInput{
      file: content,
      template_dir: state.template_dir,
      partials: state.partials,
      metadata: enrich_metadata(meta, state.partials)
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
