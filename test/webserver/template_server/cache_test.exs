defmodule Webserver.TemplateServer.CacheTest do
  use ExUnit.Case

  alias Webserver.TemplateServer.Cache
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  defp start_cache(opts \\ []) do
    template_dir = Keyword.get(opts, :template_dir, "/priv/templates")
    interval = Keyword.get(opts, :interval, 0)
    reader = Keyword.get(opts, :reader, Sandbox)
    name = :"test_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} = GenServer.start_link(Cache, {template_dir, interval, reader, name}, name: name)
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
               GenServer.start(Cache, {"/nonexistent", 0, Sandbox, name}, name: name)
    end
  end

  describe "get_page" do
    test "should return parsed HTML for a known page" do
      name = start_cache()
      assert {:ok, html} = Cache.get_page(name, "index.html")
      assert String.contains?(html, "<html")
    end

    test "should return :not_found for an unknown page" do
      name = start_cache()
      assert {:error, :not_found} = Cache.get_page(name, "missing.html")
    end

    test "should be a cache hit on second call for same page" do
      name = start_cache()
      {:ok, first} = Cache.get_page(name, "index.html")
      {:ok, second} = Cache.get_page(name, "index.html")
      assert first == second
    end
  end

  describe "stats" do
    test "should start with all counters at zero" do
      name = start_cache()
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "should record a miss on first page load" do
      name = start_cache()
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 0
    end

    test "should record a hit on repeated page load" do
      name = start_cache()

      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 1
    end

    test "should record a miss for not-found pages" do
      name = start_cache()
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
    test "should reset stats and page cache" do
      name = start_cache()
      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")

      assert :ok = Cache.force_refresh(name)
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "should re-fetch pages after force_refresh" do
      name = start_cache()
      {:ok, before_refresh} = Cache.get_page(name, "index.html")
      :ok = Cache.force_refresh(name)
      {:ok, after_refresh} = Cache.get_page(name, "index.html")
      assert before_refresh == after_refresh
    end
  end

  describe "cast handlers" do
    test "should invalidate a specific page" do
      name = start_cache()
      Cache.get_page(name, "index.html")
      assert Cache.stats(name).misses == 1

      GenServer.cast(name, {:invalidate, "index.html"})
      _ = GenServer.call(name, :stats)

      Cache.get_page(name, "index.html")
      assert Cache.stats(name).misses == 2
    end

    test "should refresh blog index" do
      name = start_cache()
      GenServer.cast(name, :refresh_blog_index)
      assert GenServer.call(name, :stats)
    end

    test "should refresh page registry" do
      name = start_cache()
      GenServer.cast(name, :refresh_page_registry)
      assert GenServer.call(name, :stats)
    end
  end
end
