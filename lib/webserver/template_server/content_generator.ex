defmodule Webserver.TemplateServer.ContentGenerator do
  @moduledoc """
  Generates dynamic content (blog index, page registry, livereload script)
  that is stored in the cache.
  """

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

  @spec generate_blog_index(map(), map()) :: String.t()
  def generate_blog_index(state, partials) do
    case state.reader.read_manifest(state.template_dir) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, posts} ->
            Enum.map_join(posts, "\n", &render_blog_item_if_exists(&1, state, partials))

          {:error, reason} ->
            Logger.warning(%{event: "blog_manifest_decode_failed", reason: reason})
            ""
        end

      _ ->
        ""
    end
  end

  @spec generate_page_registry(map()) :: [map()]
  def generate_page_registry(state) do
    pages =
      case state.reader.read_pages_manifest(state.template_dir) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, decoded} ->
              decoded

            {:error, reason} ->
              Logger.warning(%{event: "pages_manifest_decode_failed", reason: reason})
              []
          end

        _ ->
          []
      end

    Enum.filter(pages, &page_exists?(&1, state))
  end

  defp page_exists?(%{"id" => id}, state) do
    case state.reader.read_page(state.template_dir, "#{id}.html") do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp render_blog_item_if_exists(%{"id" => id} = post, state, partials) do
    case state.reader.read_page(state.template_dir, "#{id}.html") do
      {:ok, _} -> render_blog_item(post, state, partials)
      _ -> ""
    end
  end

  defp render_blog_item(post, state, partials) do
    template = """
    <% blog_index_item.html %>
    <slot:category>#{escape(post["category"])}</slot:category>
    <slot:date>#{escape(post["date"])}</slot:date>
    <slot:url>#{escape("/#{post["id"]}")}</slot:url>
    <slot:title>#{escape(post["title"])}</slot:title>
    <slot:summary>#{escape(post["summary"])}</slot:summary>
    <%/ blog_index_item.html %>
    """

    input = %ParseInput{
      file: template,
      template_dir: state.template_dir,
      partials: partials
    }

    case Parser.parse(input) do
      {:ok, html} -> html
      _ -> ""
    end
  end

  defp escape(nil), do: ""
  defp escape(value), do: Plug.HTML.html_escape(value)
end
