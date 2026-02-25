defmodule Webserver.TemplateServer.CacheTest do
  use ExUnit.Case, async: true

  alias Webserver.TemplateServer.Cache
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  defp start_cache(opts \\ []) do
    template_dir = Keyword.get(opts, :template_dir, "/priv/templates")
    interval = Keyword.get(opts, :interval, 0)
    reader = Keyword.get(opts, :reader, Sandbox)
    live_reload? = Keyword.get(opts, :live_reload, false)
    name = :"test_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      GenServer.start_link(Cache, {template_dir, interval, reader, live_reload?, name},
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
               GenServer.start(Cache, {"/nonexistent", 0, Sandbox, false, name}, name: name)
    end
  end

  describe "get_page" do
    setup do: {:ok, name: start_cache()}

    test "should return parsed HTML for a known page", %{name: name} do
      assert {:ok, html} = Cache.get_page(name, "index.html")
      assert String.contains?(html, "<html")
    end

    test "should return :not_found for an unknown page", %{name: name} do
      assert {:error, :not_found} = Cache.get_page(name, "missing.html")
    end

    test "should be a cache hit on second call for same page", %{name: name} do
      {:ok, first} = Cache.get_page(name, "index.html")
      {:ok, second} = Cache.get_page(name, "index.html")
      assert first == second
    end
  end

  describe "stats" do
    setup do: {:ok, name: start_cache()}

    test "should start with all counters at zero", %{name: name} do
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "should record a miss on first page load", %{name: name} do
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 0
    end

    test "should record a hit on repeated page load", %{name: name} do
      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 1
    end

    test "should record a miss for not-found pages", %{name: name} do
      Cache.get_page(name, "missing.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
    end

    test "should respect revalidation interval" do
      name = start_cache(interval: 1000)
      Cache.get_page(name, "index.html")
      assert Cache.stats(name).misses == 1

      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.hits == 1
      assert stats.revalidations == 0
    end
  end

  describe "force_refresh" do
    setup do: {:ok, name: start_cache()}

    test "should reset stats and page cache", %{name: name} do
      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")

      assert :ok = Cache.force_refresh(name)
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "should re-fetch pages after force_refresh", %{name: name} do
      {:ok, before_refresh} = Cache.get_page(name, "index.html")
      :ok = Cache.force_refresh(name)
      {:ok, after_refresh} = Cache.get_page(name, "index.html")
      assert before_refresh == after_refresh
    end
  end

  describe "get_sitemap" do
    setup do: {:ok, name: start_cache()}

    test "should return list of pages excluding noindex", %{name: name} do
      sitemap = Cache.get_sitemap(name)
      assert is_list(sitemap)
      assert Enum.any?(sitemap, &(&1["id"] == "index"))
      refute Enum.any?(sitemap, &(&1["id"] == "noindex-page"))
    end
  end

  describe "cast handlers" do
    setup do: {:ok, name: start_cache()}

    test "should invalidate a specific page", %{name: name} do
      Cache.get_page(name, "index.html")
      assert Cache.stats(name).misses == 1

      GenServer.cast(name, {:invalidate, "index.html"})
      _ = GenServer.call(name, :stats)

      Cache.get_page(name, "index.html")
      assert Cache.stats(name).misses == 2
    end

    test "should refresh blog index", %{name: name} do
      assert [{_, content}] =
               :ets.lookup(name, {:partial, "partials/generated_blog_items.html"})

      assert is_binary(content)

      GenServer.cast(name, :refresh_blog_index)
      _ = GenServer.call(name, :stats)

      assert [{_, _}] = :ets.lookup(name, {:partial, "partials/generated_blog_items.html"})
    end

    test "should refresh page registry", %{name: name} do
      assert [{_, pages}] = :ets.lookup(name, :page_registry)
      assert is_list(pages)

      GenServer.cast(name, :refresh_page_registry)
      _ = GenServer.call(name, :stats)

      assert [{_, ^pages}] = :ets.lookup(name, :page_registry)
    end
  end
end
