defmodule Webserver.TemplateServer.CacheTest do
  use ExUnit.Case

  alias Webserver.TemplateServer.Cache
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  defp start_cache(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "/priv/templates")
    interval = Keyword.get(opts, :interval, 0)
    reader = Keyword.get(opts, :reader, Sandbox)
    name = :"test_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} = GenServer.start_link(Cache, {base_url, interval, reader, name}, name: name)
    name
  end

  describe "init" do
    test "starts successfully with valid config" do
      name = start_cache()
      assert is_pid(GenServer.whereis(name))
    end

    test "fails to start when reader cannot find partials directory" do
      name = :"test_cache_#{System.unique_integer([:positive])}"

      assert {:error, :enoent} =
               GenServer.start(Cache, {"/nonexistent", 0, Sandbox, name}, name: name)
    end
  end

  describe "get_page" do
    test "returns parsed HTML for a known page" do
      name = start_cache()
      assert {:ok, html} = Cache.get_page(name, "index.html")
      assert String.contains?(html, "<html>")
    end

    test "returns :not_found for an unknown page" do
      name = start_cache()
      assert {:error, :not_found} = Cache.get_page(name, "missing.html")
    end

    test "second call for same page is a cache hit" do
      name = start_cache()
      {:ok, first} = Cache.get_page(name, "index.html")
      {:ok, second} = Cache.get_page(name, "index.html")
      assert first == second
    end
  end

  describe "stats" do
    test "starts with all counters at zero" do
      name = start_cache()
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "records a miss on first page load" do
      name = start_cache()
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 0
    end

    test "records a hit on repeated page load" do
      name = start_cache()

      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
      assert stats.hits == 1
    end

    test "records a miss for not-found pages" do
      name = start_cache()
      Cache.get_page(name, "missing.html")
      stats = Cache.stats(name)
      assert stats.misses == 1
    end
  end

  describe "force_refresh" do
    test "resets stats and page cache" do
      name = start_cache()
      Cache.get_page(name, "index.html")
      Cache.get_page(name, "index.html")

      assert :ok = Cache.force_refresh(name)
      assert Cache.stats(name) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "pages are re-fetched after force_refresh" do
      name = start_cache()
      {:ok, before_refresh} = Cache.get_page(name, "index.html")
      :ok = Cache.force_refresh(name)
      {:ok, after_refresh} = Cache.get_page(name, "index.html")
      assert before_refresh == after_refresh
    end
  end
end
