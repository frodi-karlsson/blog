defmodule Webserver.Content.Builder do
  @moduledoc """
  Builds all generated content: the blog index partial, posts DB, tags index,
  per-tag pages, page registry, and the livereload partial.

  Pure. `build/1` computes rows and returns them; `Webserver.Content.Store`
  performs the ETS writes. Keeping the writes out means content generation is
  testable without starting a process.
  """

  alias Webserver.Content.Generator
  alias Webserver.Content.PageEntry
  alias Webserver.Parser.PartialMeta

  @blog_key "partials/generated_blog_items.html"
  @livereload_key "partials/generated_livereload_script.html"

  @type result :: %{
          rows: [{term(), term()}],
          partials: map(),
          tag_page_filenames: MapSet.t(String.t())
        }

  @spec build(map()) :: result()
  def build(state) do
    livereload = Generator.generate_livereload_partial(state.live_reload?)
    partials = Map.put(state.partials, @livereload_key, livereload)
    partial_meta = PartialMeta.build_all(partials)

    pages_meta = Generator.scan_pages(state)

    blog_index = Generator.generate_blog_index(pages_meta, state, partials, partial_meta)
    partials = Map.put(partials, @blog_key, blog_index)
    partial_meta = Map.put(partial_meta, @blog_key, PartialMeta.build(blog_index))

    posts = Generator.build_posts_db(pages_meta)
    registry = Generator.generate_page_registry(pages_meta)

    tags_index = Generator.generate_tags_index_page(posts, state, partials, partial_meta)
    tag_pages = Generator.generate_tag_pages(posts, state, partials, partial_meta)

    tag_page_rows =
      Enum.map(tag_pages, fn {tag, html} ->
        {{:page, "tags/#{tag}.html"}, generated_entry(html)}
      end)

    rows =
      [
        {:partials, partials},
        {:partial_meta, partial_meta},
        {:posts_db, posts},
        {:page_registry, registry},
        {:page_path_set, page_path_set(registry)},
        {{:page, "tags/index.html"}, generated_entry(tags_index)}
      ] ++ tag_page_rows

    %{
      rows: rows,
      partials: partials,
      tag_page_filenames: MapSet.new(tag_pages, fn {tag, _} -> "tags/#{tag}.html" end)
    }
  end

  defp generated_entry(html) do
    %PageEntry{
      parsed: html,
      mtime: :generated,
      last_checked_at: System.system_time(:millisecond)
    }
  end

  # Published alongside the registry so the metrics handler can test a path
  # with a set lookup instead of scanning every page on each request.
  defp page_path_set(registry) do
    registry
    |> Enum.flat_map(fn
      %{"path" => path} when is_binary(path) -> [path]
      _ -> []
    end)
    |> MapSet.new()
  end
end
