defmodule Webserver.Content.Query do
  @moduledoc """
  Read-only queries over generated content.

  These read ETS rows written by `Webserver.Content.Store` and filter them. They
  hold no caching semantics and start no process, so they run in the calling
  process with no round trip.

  The first argument is the table name, which is also the `Store` process name.
  """

  alias Webserver.Content.Post

  @default_table Webserver.Content.Store

  @spec list_posts(atom()) :: [Post.t()]
  def list_posts(table \\ @default_table) do
    case :ets.lookup(table, :posts_db) do
      [{:posts_db, posts}] -> posts
      _ -> []
    end
  end

  @spec posts_by_tag(atom(), String.t()) :: [Post.t()]
  def posts_by_tag(table \\ @default_table, tag) do
    needle = String.downcase(tag)
    Enum.filter(list_posts(table), fn post -> needle in post.tags end)
  end

  @spec search_posts(atom(), String.t()) :: [Post.t()]
  def search_posts(table \\ @default_table, query) do
    q = query |> String.trim() |> String.downcase() |> String.slice(0, 200)

    if q == "" do
      list_posts(table)
    else
      Enum.filter(list_posts(table), fn post ->
        String.contains?(String.downcase(post.title), q) or
          String.contains?(String.downcase(post.summary), q)
      end)
    end
  end

  @spec all_tags(atom()) :: [{String.t(), non_neg_integer()}]
  def all_tags(table \\ @default_table) do
    table
    |> list_posts()
    |> Enum.flat_map(& &1.tags)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
  end

  @spec get_sitemap(atom()) :: [map()]
  def get_sitemap(table \\ @default_table) do
    case :ets.lookup(table, :page_registry) do
      [{_, pages}] -> Enum.reject(pages, &Map.get(&1, "noindex", false))
      _ -> []
    end
  end

  @doc """
  Whether `path` is a known page path. Backs the metrics handler's cardinality
  guard, so it must never raise and must be cheap enough for the request path.
  """
  @spec page_path?(atom(), String.t()) :: boolean()
  def page_path?(table \\ @default_table, path) do
    case :ets.lookup(table, :page_path_set) do
      [{:page_path_set, %MapSet{} = paths}] -> MapSet.member?(paths, path)
      _ -> false
    end
  rescue
    ArgumentError -> false
  end
end
