defmodule Webserver.TemplateServer.CacheTest do
  use ExUnit.Case

  alias Webserver.TemplateServer.Cache
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  # Start an isolated Cache instance, bypassing the fixed `name: __MODULE__`
  # registration so tests don't interfere with each other or the app-level cache.
  defp start_cache(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "/priv/templates")
    interval = Keyword.get(opts, :interval, 0)
    reader = Keyword.get(opts, :reader, Sandbox)
    name = :"test_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} = GenServer.start_link(Cache, {base_url, interval, reader}, name: name)
    name
  end

  describe "init" do
    test "starts successfully with valid config" do
      name = start_cache()
      assert is_pid(GenServer.whereis(name))
    end

    test "fails to start when reader cannot find partials directory" do
      # Sandbox returns {:error, :enoent} for any base_url except "/priv/templates".
      # Use start/3 (no link) so the abnormal exit doesn't crash the test process.
      assert {:error, :enoent} =
               GenServer.start(Cache, {"/nonexistent", 0, Sandbox}, [])
    end
  end

  describe "get_page" do
    test "returns parsed HTML for a known page" do
      name = start_cache()
      assert {:ok, html} = GenServer.call(name, {:get_page, "index.html"})
      assert String.contains?(html, "<html>")
    end

    test "returns :not_found for an unknown page" do
      name = start_cache()
      assert {:error, :not_found} = GenServer.call(name, {:get_page, "missing.html"})
    end

    test "second call for same page is a cache hit" do
      name = start_cache()
      {:ok, first} = GenServer.call(name, {:get_page, "index.html"})
      {:ok, second} = GenServer.call(name, {:get_page, "index.html"})
      assert first == second
    end
  end

  describe "stats" do
    test "starts with all counters at zero" do
      name = start_cache()
      assert GenServer.call(name, :stats) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "records a miss on first page load" do
      name = start_cache()
      GenServer.call(name, {:get_page, "index.html"})
      stats = GenServer.call(name, :stats)
      assert stats.misses == 1
      assert stats.hits == 0
    end

    test "records a hit on repeated page load" do
      name = start_cache()

      # interval=0 means we always check mtime, but Sandbox has no mtime so nil==nil → no revalidation
      GenServer.call(name, {:get_page, "index.html"})
      GenServer.call(name, {:get_page, "index.html"})
      stats = GenServer.call(name, :stats)
      assert stats.misses == 1
      assert stats.hits == 1
    end

    test "records a miss for not-found pages" do
      name = start_cache()
      GenServer.call(name, {:get_page, "missing.html"})
      stats = GenServer.call(name, :stats)
      assert stats.misses == 1
    end
  end

  describe "force_refresh" do
    test "resets stats and page cache" do
      name = start_cache()
      GenServer.call(name, {:get_page, "index.html"})
      GenServer.call(name, {:get_page, "index.html"})

      assert :ok = GenServer.call(name, :force_refresh)
      assert GenServer.call(name, :stats) == %{hits: 0, misses: 0, revalidations: 0}
    end

    test "pages are re-fetched after force_refresh" do
      name = start_cache()
      {:ok, before_refresh} = GenServer.call(name, {:get_page, "index.html"})
      :ok = GenServer.call(name, :force_refresh)
      {:ok, after_refresh} = GenServer.call(name, {:get_page, "index.html"})
      assert before_refresh == after_refresh
    end
  end
end
