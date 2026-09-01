defmodule Webserver.Content.StoreTest do
  use ExUnit.Case, async: true

  alias Webserver.Content.Store
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
end
