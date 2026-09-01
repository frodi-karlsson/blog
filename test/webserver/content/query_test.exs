defmodule Webserver.Content.QueryTest do
  use ExUnit.Case, async: true

  alias Webserver.Content.Query
  alias Webserver.Content.Store
  alias Webserver.Content.TemplateReader.Sandbox

  defp start_store do
    name = :"test_store_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      GenServer.start_link(Store, {"/priv/templates", 0, Sandbox, false, name}, name: name)

    name
  end

  setup do: {:ok, name: start_store()}

  test "list_posts returns posts sorted by date descending", %{name: name} do
    posts = Query.list_posts(name)
    assert is_list(posts)
    refute posts == []
    dates = Enum.map(posts, & &1.date)
    assert dates == Enum.sort(dates, {:desc, Date})
  end

  test "posts_by_tag matches case-insensitively", %{name: name} do
    case Query.list_posts(name) do
      [%{tags: [tag | _]} | _] ->
        assert Query.posts_by_tag(name, String.upcase(tag)) != []

      _ ->
        flunk("fixture has no tagged posts")
    end
  end

  test "search_posts with a blank query returns every post", %{name: name} do
    assert Query.search_posts(name, "   ") == Query.list_posts(name)
  end

  test "all_tags returns tags sorted by count descending then name", %{name: name} do
    tags = Query.all_tags(name)
    assert tags == Enum.sort_by(tags, fn {tag, count} -> {-count, tag} end)
  end

  test "get_sitemap excludes noindex pages and keeps the rest", %{name: name} do
    :ets.insert(
      name,
      {:page_registry,
       [
         %{"id" => "visible", "path" => "/visible"},
         %{"id" => "hidden", "path" => "/hidden", "noindex" => true}
       ]}
    )

    paths = Enum.map(Query.get_sitemap(name), & &1["path"])

    assert "/visible" in paths
    refute "/hidden" in paths
  end

  test "page_path? is true for a registered path and false otherwise", %{name: name} do
    assert Query.page_path?(name, "/")
    refute Query.page_path?(name, "/definitely-not-a-real-page")
  end

  describe "get_sitemap" do
    setup do: {:ok, name: start_store()}

    test "should return list of pages excluding noindex", %{name: name} do
      sitemap = Query.get_sitemap(name)
      assert is_list(sitemap)
      assert Enum.any?(sitemap, &(&1["id"] == "index"))
      refute Enum.any?(sitemap, &(&1["id"] == "noindex-page"))
    end
  end

  describe "posts DB queries" do
    setup do: {:ok, name: start_store()}

    test "list_posts/1 returns all blog posts, date desc", %{name: name} do
      posts = Query.list_posts(name)
      ids = Enum.map(posts, & &1.id)
      assert "post-a" in ids
      assert "post-b" in ids
      # Post A dated 2026-05-01, Post B dated 2026-04-01
      assert Enum.find_index(ids, &(&1 == "post-a")) <
               Enum.find_index(ids, &(&1 == "post-b"))
    end

    test "posts_by_tag/2 filters case-insensitively", %{name: name} do
      posts = Query.posts_by_tag(name, "TypeScript")
      assert Enum.map(posts, & &1.id) == ["post-a"]
    end

    test "posts_by_tag/2 returns empty list for unknown tag", %{name: name} do
      assert Query.posts_by_tag(name, "nonexistent") == []
    end

    test "search_posts/2 matches on title", %{name: name} do
      posts = Query.search_posts(name, "post a")
      assert Enum.map(posts, & &1.id) == ["post-a"]
    end

    test "search_posts/2 matches on summary", %{name: name} do
      posts = Query.search_posts(name, "about b")
      assert Enum.map(posts, & &1.id) == ["post-b"]
    end

    test "search_posts/2 is case-insensitive", %{name: name} do
      posts = Query.search_posts(name, "POST A")
      assert Enum.map(posts, & &1.id) == ["post-a"]
    end

    test "search_posts/2 with empty query returns all posts", %{name: name} do
      all = Query.list_posts(name)
      assert Query.search_posts(name, "") == all
      assert Query.search_posts(name, "   ") == all
    end

    test "all_tags/1 returns tags with counts, sorted", %{name: name} do
      tags = Query.all_tags(name)
      assert {"anabranch", 1} in tags
      assert {"typescript", 1} in tags
      assert {"elixir", 1} in tags
    end
  end
end
