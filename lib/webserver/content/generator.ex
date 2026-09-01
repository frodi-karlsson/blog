defmodule Webserver.Content.Generator do
  @moduledoc """
  Generates dynamic content (blog index, page registry, livereload script)
  that is stored in the cache.
  """

  alias Webserver.Content.BlogItemRenderer
  alias Webserver.Content.Post
  alias Webserver.FrontMatter
  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  require Logger

  @spec generate_livereload_partial(boolean()) :: String.t()
  def generate_livereload_partial(live_reload?) do
    if live_reload? do
      ~S|<script src="/static/js/livereload.js"></script>|
    else
      ""
    end
  end

  @spec scan_pages(map()) :: [{String.t(), map()}]
  def scan_pages(state) do
    case state.reader.list_pages(state.template_dir) do
      {:ok, filenames} ->
        Enum.map(filenames, &read_meta(&1, state))

      {:error, reason} ->
        Logger.warning(%{event: "list_pages_failed", reason: reason})
        []
    end
  end

  defp read_meta(filename, state) do
    case state.reader.read_page(state.template_dir, filename) do
      {:ok, content} ->
        {meta, _body} = FrontMatter.parse(content)
        {filename, meta}

      _ ->
        {filename, %{}}
    end
  end

  @spec generate_blog_index([{String.t(), map()}], map(), map(), map()) :: String.t()
  def generate_blog_index(pages_meta, state, partials, partial_meta) do
    pages_meta
    |> Enum.filter(fn {_filename, meta} -> FrontMatter.blog_post?(meta) end)
    |> Enum.sort_by(fn {_filename, meta} -> meta["date"] end, :desc)
    |> Enum.map_join("\n", fn {filename, meta} ->
      BlogItemRenderer.render(filename, meta, state.template_dir, partials, partial_meta)
    end)
  end

  @spec generate_page_registry([{String.t(), map()}]) :: [map()]
  def generate_page_registry(pages_meta) do
    pages_meta
    |> Enum.reject(fn {_filename, meta} -> meta == %{} end)
    |> Enum.map(&build_registry_entry/1)
  end

  defp build_registry_entry({filename, meta}) do
    id = Path.rootname(filename)
    path = meta["path"] || FrontMatter.derive_path(filename)
    entry = %{"id" => id, "title" => meta["title"], "path" => path}
    if meta["noindex"] == "true", do: Map.put(entry, "noindex", true), else: entry
  end

  @spec build_posts_db([{String.t(), map()}]) :: [Post.t()]
  def build_posts_db(pages_meta) do
    pages_meta
    |> Enum.filter(fn {_filename, meta} -> FrontMatter.blog_post?(meta) end)
    |> Enum.reduce([], fn {filename, meta}, acc ->
      case build_post(filename, meta) do
        {:ok, post} ->
          [post | acc]

        {:error, reason} ->
          Logger.warning(%{event: "post_build_failed", filename: filename, reason: reason})
          acc
      end
    end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp build_post(filename, meta) do
    with {:ok, date} <- parse_date(meta["date"]) do
      {:ok,
       %Post{
         id: Path.rootname(filename),
         filename: filename,
         path: meta["path"] || FrontMatter.derive_path(filename),
         title: meta["title"] || "",
         date: date,
         summary: meta["summary"] || "",
         tags: FrontMatter.parse_tags(meta["tags"]),
         canonical: meta["canonical"],
         noindex: meta["noindex"] == "true"
       }}
    end
  end

  defp parse_date(nil), do: {:error, :missing_date}

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, reason} -> {:error, {:invalid_date, reason}}
    end
  end

  @spec generate_tags_index_page([Post.t()], map(), map(), map()) :: String.t()
  def generate_tags_index_page(posts, state, partials, partial_meta) do
    tags_with_counts =
      posts
      |> Enum.flat_map(& &1.tags)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)

    chips =
      Enum.map_join(tags_with_counts, "\n", fn {tag, count} ->
        escaped = Plug.HTML.html_escape(tag)

        ~s|<a href="/tags/#{escaped}" class="badge badge--secondary badge--pill" data-testid="tag-chip">#{escaped} (#{count})</a>|
      end)

    page_template = """
    <% layout.html %>
      <slot:title>Tags</slot:title>
      <slot:description>All tags on the blog</slot:description>
      <slot:canonical></slot:canonical>
      <slot:og_type>website</slot:og_type>
      <slot:body>
        <% tags_index.html %>
          <slot:chips>#{chips}</slot:chips>
        <%/ tags_index.html %>
      </slot:body>
    <%/ layout.html %>
    """

    input = %ParseInput{
      file: page_template,
      template_dir: state.template_dir,
      partials: partials,
      partial_meta: partial_meta
    }

    case Parser.parse(input) do
      {:ok, html} ->
        html

      {:error, reason} ->
        Logger.warning(%{event: "tags_index_generate_failed", reason: reason})
        ""
    end
  end

  @spec generate_tag_pages([Post.t()], map(), map(), map()) :: %{String.t() => String.t()}
  def generate_tag_pages(posts, state, partials, partial_meta) do
    posts
    |> Enum.flat_map(& &1.tags)
    |> Enum.uniq()
    |> Map.new(fn tag ->
      {tag, generate_tag_page(tag, posts, state, partials, partial_meta)}
    end)
  end

  defp generate_tag_page(tag, all_posts, state, partials, partial_meta) do
    matching = Enum.filter(all_posts, fn post -> tag in post.tags end)

    items =
      Enum.map_join(matching, "\n", fn post ->
        BlogItemRenderer.render(
          post.filename,
          Post.to_meta(post),
          state.template_dir,
          partials,
          partial_meta
        )
      end)

    escaped_tag = Plug.HTML.html_escape(tag)

    page_template = """
    <% layout.html %>
      <slot:title>Posts tagged #{escaped_tag}</slot:title>
      <slot:description>All posts tagged #{escaped_tag}</slot:description>
      <slot:canonical></slot:canonical>
      <slot:og_type>website</slot:og_type>
      <slot:body>
        <% tag_page.html %>
          <slot:tag>#{escaped_tag}</slot:tag>
          <slot:items>#{items}</slot:items>
        <%/ tag_page.html %>
      </slot:body>
    <%/ layout.html %>
    """

    input = %ParseInput{
      file: page_template,
      template_dir: state.template_dir,
      partials: partials,
      partial_meta: partial_meta
    }

    case Parser.parse(input) do
      {:ok, html} -> html
      _ -> ""
    end
  end
end
