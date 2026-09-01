defmodule Webserver.Content.StoreTest do
  use ExUnit.Case, async: true

  alias Webserver.Content.Store
  alias Webserver.Content.TemplateReader.MutableSandbox
  alias Webserver.Content.TemplateReader.Sandbox

  defp start_cache(opts \\ []) do
    template_dir = Keyword.get(opts, :template_dir, "/priv/templates")
    interval = Keyword.get(opts, :interval, 0)
    reader = Keyword.get(opts, :reader, Sandbox)
    live_reload? = Keyword.get(opts, :live_reload, false)
    name = :"test_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      GenServer.start_link(Store, {template_dir, interval, reader, live_reload?, name},
        name: name
      )

    name
  end

  describe "init" do
    test "should start successfully with valid config" do
      name = start_cache()
      assert is_pid(GenServer.whereis(name))
    end

    test "should fail to start when reader cannot find partials directory" do
      name = :"test_cache_#{System.unique_integer([:positive])}"

      assert {:error, :not_found} =
               GenServer.start(Store, {"/nonexistent", 0, Sandbox, false, name}, name: name)
    end
  end

  describe "get_page" do
    setup do: {:ok, name: start_cache()}

    test "should return parsed HTML for a known page", %{name: name} do
      assert {:ok, html} = Store.get_page(name, "index.html")
      assert String.contains?(html, "<html")
    end

    test "should return :not_found for an unknown page", %{name: name} do
      assert {:error, :not_found} = Store.get_page(name, "missing.html")
    end

    test "should be a cache hit on second call for same page", %{name: name} do
      {:ok, first} = Store.get_page(name, "index.html")
      {:ok, second} = Store.get_page(name, "index.html")
      assert first == second
    end
  end

  describe "cache miss path" do
    test "a miss is served without a GenServer round trip" do
      name = start_cache()

      # Evict so the next read is a genuine miss.
      :ets.delete(name, {:page, "index.html"})

      pid = GenServer.whereis(name)
      :sys.suspend(pid)

      try do
        assert {:ok, html} = Store.get_page(name, "index.html")
        assert html =~ "<html"
      after
        :sys.resume(pid)
      end
    end

    test "a miss caches the parsed page for subsequent reads" do
      name = start_cache()
      :ets.delete(name, {:page, "index.html"})

      {:ok, first} = Store.get_page(name, "index.html")
      assert [{_, entry}] = :ets.lookup(name, {:page, "index.html"})
      assert entry.parsed == first

      {:ok, second} = Store.get_page(name, "index.html")
      assert second == first
    end

    test "concurrent misses on the same path all return the same correct HTML" do
      name = start_cache()
      :ets.delete(name, {:page, "index.html"})

      results =
        1..20
        |> Task.async_stream(fn _ -> Store.get_page(name, "index.html") end,
          max_concurrency: 20,
          timeout: 5000
        )
        |> Enum.map(fn {:ok, res} -> res end)

      assert Enum.all?(results, &match?({:ok, _}, &1))
      assert results |> Enum.map(fn {:ok, html} -> html end) |> Enum.uniq() |> length() == 1
    end

    test "a missing page still reports not_found" do
      name = start_cache()
      assert {:error, :not_found} = Store.get_page(name, "definitely-missing.html")
    end
  end

  describe "stats" do
    setup do: {:ok, name: start_cache()}

    test "should start with all counters at zero", %{name: name} do
      assert Store.stats(name) == %{hits: 0, misses: 0, revalidations: 0, revalidation_errors: 0}
    end

    test "should record a miss on first page load", %{name: name} do
      Store.get_page(name, "index.html")
      stats = Store.stats(name)
      assert stats.misses == 1
      assert stats.hits == 0
    end

    test "should record a hit on repeated page load", %{name: name} do
      Store.get_page(name, "index.html")
      Store.get_page(name, "index.html")
      stats = Store.stats(name)
      assert stats.misses == 1
      assert stats.hits == 1
    end

    test "should record a miss for not-found pages", %{name: name} do
      Store.get_page(name, "missing.html")
      stats = Store.stats(name)
      assert stats.misses == 1
    end

    test "should respect revalidation interval" do
      name = start_cache(interval: 1000)
      Store.get_page(name, "index.html")
      assert Store.stats(name).misses == 1

      Store.get_page(name, "index.html")
      stats = Store.stats(name)
      assert stats.hits == 1
      assert stats.revalidations == 0
    end
  end

  describe "force_refresh" do
    setup do: {:ok, name: start_cache()}

    test "should reset stats and page cache", %{name: name} do
      Store.get_page(name, "index.html")
      Store.get_page(name, "index.html")

      assert :ok = Store.force_refresh(name)
      assert Store.stats(name) == %{hits: 0, misses: 0, revalidations: 0, revalidation_errors: 0}
    end

    test "should re-fetch pages after force_refresh", %{name: name} do
      {:ok, before_refresh} = Store.get_page(name, "index.html")
      :ok = Store.force_refresh(name)
      {:ok, after_refresh} = Store.get_page(name, "index.html")
      assert before_refresh == after_refresh
    end
  end

  describe "partials generation eviction" do
    test "a page cached against an older partials generation does not survive a regeneration" do
      name = start_cache()

      {:ok, _} = Store.get_page(name, "index.html")

      # Stand in for a page cached mid-refresh against the previous partials: a
      # file-backed entry whose content predates the current partials row. Its
      # mtime is unchanged, so revalidation would never correct it.
      [{_, entry}] = :ets.lookup(name, {:page, "index.html"})
      :ets.insert(name, {{:page, "index.html"}, %{entry | parsed: "<p>stale</p>"}})

      # Driven through :refresh_content rather than force_refresh on purpose:
      # force_refresh wipes every page row before regenerating, so it would
      # remove this entry whether or not the post-generation eviction runs.
      GenServer.cast(name, :refresh_content)
      _ = GenServer.call(name, :stats)

      case :ets.lookup(name, {:page, "index.html"}) do
        [] -> :ok
        [{_, refreshed}] -> refute refreshed.parsed == "<p>stale</p>"
      end
    end

    test "generated pages are not evicted by a regeneration or a force_refresh" do
      name = start_cache()

      GenServer.cast(name, :refresh_content)
      _ = GenServer.call(name, :stats)

      assert [{_, entry}] = :ets.lookup(name, {:page, "tags/index.html"})
      assert entry.mtime == :generated

      assert :ok = Store.force_refresh(name)

      assert [{_, _}] = :ets.lookup(name, {:page, "tags/index.html"}),
             "generated pages have no file to re-read, so evicting them would 404 them"
    end
  end

  describe "cast handlers" do
    setup do: {:ok, name: start_cache()}

    test "should invalidate a specific page", %{name: name} do
      Store.get_page(name, "index.html")
      assert Store.stats(name).misses == 1

      GenServer.cast(name, {:invalidate, "index.html"})
      _ = GenServer.call(name, :stats)

      Store.get_page(name, "index.html")
      assert Store.stats(name).misses == 2
    end

    test "should refresh blog index and page registry together", %{name: name} do
      assert [{:partials, partials}] = :ets.lookup(name, :partials)
      assert Map.has_key?(partials, "partials/generated_blog_items.html")

      assert [{_, pages}] = :ets.lookup(name, :page_registry)
      assert is_list(pages)

      GenServer.cast(name, :refresh_content)
      _ = GenServer.call(name, :stats)

      assert [{:partials, partials}] = :ets.lookup(name, :partials)
      assert Map.has_key?(partials, "partials/generated_blog_items.html")
      assert [{_, ^pages}] = :ets.lookup(name, :page_registry)
    end
  end

  describe "get_partials" do
    setup do: {:ok, name: start_cache()}

    test "reads partials without a GenServer round trip", %{name: name} do
      # Suspending the GenServer proves the read never touches it: if
      # get_partials/1 still went through the process, this would time out.
      pid = GenServer.whereis(name)
      :sys.suspend(pid)

      try do
        assert {:ok, partials} = Store.get_partials(name)
        assert is_map(partials)
        assert Map.has_key?(partials, "partials/layout.html")
        assert Map.has_key?(partials, "partials/generated_blog_items.html")
      after
        :sys.resume(pid)
      end
    end

    test "publishes the partials map as a single ETS row", %{name: name} do
      assert [{:partials, partials}] = :ets.lookup(name, :partials)
      assert is_map(partials)
      assert Map.has_key?(partials, "partials/generated_blog_items.html")
    end
  end

  describe "get_partial_meta" do
    setup do: {:ok, name: start_cache()}

    test "reads partial meta without a GenServer round trip", %{name: name} do
      pid = GenServer.whereis(name)
      :sys.suspend(pid)

      try do
        assert {:ok, meta} = Store.get_partial_meta(name)
        assert is_map(meta)
        assert Map.has_key?(meta, "partials/layout.html")
      after
        :sys.resume(pid)
      end
    end

    test "has an entry for every partial, so the parser's lookup always hits", %{name: name} do
      {:ok, partials} = Store.get_partials(name)
      {:ok, partial_meta} = Store.get_partial_meta(name)

      assert Map.keys(partial_meta) |> Enum.sort() == Map.keys(partials) |> Enum.sort()
    end

    test "layout.html's meta reflects the slots it actually declares", %{name: name} do
      {:ok, partials} = Store.get_partials(name)
      {:ok, partial_meta} = Store.get_partial_meta(name)

      alias Webserver.Parser.PartialMeta
      expected = PartialMeta.build(Map.fetch!(partials, "partials/layout.html"))

      assert partial_meta["partials/layout.html"] == expected
    end
  end

  describe "tags landing page" do
    setup do: {:ok, name: start_cache()}

    test "GET /tags returns 200 with the tags-index HTML", %{name: name} do
      assert {:ok, html} = Store.get_page(name, "tags/index.html")
      assert html =~ "Tags"
      assert html =~ "anabranch"
      assert html =~ "typescript"
      assert html =~ "elixir"
    end

    test "each tag chip links to /tags/<name>", %{name: name} do
      {:ok, html} = Store.get_page(name, "tags/index.html")
      assert html =~ ~s|href="/tags/anabranch"|
      assert html =~ ~s|href="/tags/typescript"|
    end

    test "chip label includes count", %{name: name} do
      {:ok, html} = Store.get_page(name, "tags/index.html")
      assert html =~ ~r|anabranch.*\(1\)|
    end
  end

  describe "per-tag pages" do
    setup do: {:ok, name: start_cache()}

    test "GET /tags/anabranch returns 200 with only posts in that tag", %{name: name} do
      assert {:ok, html} = Store.get_page(name, "tags/anabranch.html")
      assert html =~ "anabranch"
      assert html =~ "post-a"
      refute html =~ "post-b"
    end

    test "GET /tags/nonexistent returns not_found", %{name: name} do
      assert {:error, :not_found} = Store.get_page(name, "tags/nonexistent.html")
    end

    test "tag pages are lowercased", %{name: name} do
      # Post A has 'TypeScript' in tags; parse_tags lowercases it.
      assert {:ok, _} = Store.get_page(name, "tags/typescript.html")
      assert {:error, :not_found} = Store.get_page(name, "tags/TypeScript.html")
    end

    test "tag pages have a back link to /tags", %{name: name} do
      {:ok, html} = Store.get_page(name, "tags/anabranch.html")
      assert html =~ ~s|href="/tags"|
    end
  end

  describe "revalidation timestamp semantics" do
    setup do
      {:ok, _} = MutableSandbox.start_link(%{"index.html" => mutable_index_page()})

      on_exit(fn ->
        try do
          MutableSandbox.stop()
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "a failed revalidation does not advance last_checked_at" do
      name = start_cache(reader: MutableSandbox, interval: 0)

      {:ok, _} = Store.get_page(name, "index.html")
      [{_, before_entry}] = :ets.lookup(name, {:page, "index.html"})

      # Make the page unparseable. put_page/2 also bumps the mtime, so
      # revalidation will attempt a reparse and fail.
      MutableSandbox.put_page("index.html", "<% nonexistent_partial.html %/>")

      # Pin last_checked_at to a value the clock can never produce, so the
      # assertion below cannot pass by accident on a millisecond clock that
      # simply has not ticked between the two requests.
      :ets.insert(name, {{:page, "index.html"}, %{before_entry | last_checked_at: 0}})
      before_entry = %{before_entry | last_checked_at: 0}

      {:ok, _} = Store.get_page(name, "index.html")
      Process.sleep(50)

      [{_, after_entry}] = :ets.lookup(name, {:page, "index.html"})

      assert after_entry.last_checked_at == before_entry.last_checked_at,
             "a failed revalidation must not advance last_checked_at, or the page waits a full interval to retry"

      assert after_entry.parsed == before_entry.parsed, "content must stay as it was"
      assert Store.stats(name).revalidation_errors >= 1
    end

    test "a successful revalidation updates content and advances last_checked_at" do
      name = start_cache(reader: MutableSandbox, interval: 0)

      {:ok, first} = Store.get_page(name, "index.html")
      [{_, before_entry}] = :ets.lookup(name, {:page, "index.html"})

      MutableSandbox.put_page("index.html", "<p>rewritten</p>")

      {:ok, _} = Store.get_page(name, "index.html")
      Process.sleep(50)

      [{_, after_entry}] = :ets.lookup(name, {:page, "index.html"})

      assert after_entry.parsed =~ "rewritten"
      assert after_entry.parsed != first
      assert after_entry.last_checked_at >= before_entry.last_checked_at
      assert Store.stats(name).revalidations >= 1
    end

    test "an unchanged page advances last_checked_at without rewriting content" do
      name = start_cache(interval: 60_000)

      {:ok, _} = Store.get_page(name, "index.html")
      [{_, first}] = :ets.lookup(name, {:page, "index.html"})

      # Force the entry to look stale.
      :ets.insert(name, {{:page, "index.html"}, %{first | last_checked_at: 0}})

      {:ok, _} = Store.get_page(name, "index.html")
      Process.sleep(50)

      [{_, second}] = :ets.lookup(name, {:page, "index.html"})

      assert second.last_checked_at > 0,
             "an unchanged page must advance last_checked_at, or every request re-triggers revalidation"

      assert second.parsed == first.parsed
    end

    test "generated pages never schedule revalidation" do
      name = start_cache(interval: 0)

      # The in-flight marker is cleared by handle_cast's `after` clause, so a
      # running server would erase the evidence either way. Suspending it
      # freezes the mailbox: if a cast were scheduled, the marker that guards
      # it would still be sitting in the table.
      pid = GenServer.whereis(name)
      :sys.suspend(pid)

      try do
        {:ok, _} = Store.get_page(name, "tags/index.html")

        assert :ets.lookup(name, {:revalidate_in_flight, "tags/index.html"}) == [],
               "a generated page has no file behind it, so it must not schedule revalidation"
      after
        :sys.resume(pid)
      end

      assert Store.stats(name).revalidations == 0
    end
  end

  defp mutable_index_page do
    """
    ---
    title: Home
    ---
    <% layout.html %>
      <slot:title>Home</slot:title>
      <slot:description>d</slot:description>
      <slot:canonical></slot:canonical>
      <slot:og_type>website</slot:og_type>
      <slot:body><h1>Home</h1></slot:body>
    <%/ layout.html %>
    """
  end
end
