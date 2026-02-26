defmodule Webserver.TemplateServer.ContentGenerator do
  @moduledoc """
  Generates dynamic content (blog index, page registry, livereload script)
  that is stored in the cache.
  """

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

  @spec generate_blog_index(map(), map()) :: String.t()
  def generate_blog_index(state, partials) do
    case state.reader.list_pages(state.template_dir) do
      {:ok, filenames} ->
        filenames
        |> Enum.map(&read_with_meta(&1, state))
        |> Enum.filter(fn {_filename, meta} -> FrontMatter.blog_post?(meta) end)
        |> Enum.sort_by(fn {_filename, meta} -> meta["date"] end, :desc)
        |> Enum.map_join("\n", fn {filename, meta} ->
          render_blog_item(filename, meta, state, partials)
        end)

      {:error, reason} ->
        Logger.warning(%{event: "list_pages_failed", reason: reason})
        ""
    end
  end

  @spec generate_page_registry(map()) :: [map()]
  def generate_page_registry(state) do
    case state.reader.list_pages(state.template_dir) do
      {:ok, filenames} ->
        filenames
        |> Enum.map(&read_with_meta(&1, state))
        |> Enum.reject(fn {_filename, meta} -> meta == %{} end)
        |> Enum.map(&build_registry_entry/1)

      {:error, reason} ->
        Logger.warning(%{event: "list_pages_failed", reason: reason})
        []
    end
  end

  defp build_registry_entry({filename, meta}) do
    id = Path.rootname(filename)
    path = meta["path"] || FrontMatter.derive_path(filename)
    entry = %{"id" => id, "title" => meta["title"], "path" => path}
    if meta["noindex"] == "true", do: Map.put(entry, "noindex", true), else: entry
  end

  defp read_with_meta(filename, state) do
    case state.reader.read_page(state.template_dir, filename) do
      {:ok, content} ->
        {meta, _body} = FrontMatter.parse(content)
        {filename, meta}

      _ ->
        {filename, %{}}
    end
  end

  defp render_blog_item(filename, meta, state, partials) do
    url = meta["path"] || FrontMatter.derive_path(filename)
    date = FrontMatter.format_date(meta["date"] || "")

    template = """
    <% blog_index_item.html %>
    <slot:category>#{escape(meta["category"])}</slot:category>
    <slot:date>#{escape(date)}</slot:date>
    <slot:url>#{escape(url)}</slot:url>
    <slot:title>#{escape(meta["title"])}</slot:title>
    <slot:summary>#{escape(meta["summary"])}</slot:summary>
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
