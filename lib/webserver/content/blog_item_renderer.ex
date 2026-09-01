defmodule Webserver.Content.BlogItemRenderer do
  @moduledoc """
  Renders a single blog index item using the `blog_index_item.html` partial.
  Used both at cache-init time (for the pre-rendered blog index) and at
  request time (for search results).
  """

  alias Webserver.FrontMatter
  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  @spec render(String.t(), map(), String.t(), map(), map(), map()) :: String.t()
  def render(
        filename,
        meta,
        template_dir,
        partials,
        partial_meta \\ %{},
        compiled_partials \\ %{}
      ) do
    url = meta["path"] || FrontMatter.derive_path(filename)
    date = FrontMatter.format_date(meta["date"] || "")
    tags = normalize_tags(meta["tags"])

    template = """
    <% blog_index_item.html %>
    <slot:tags>#{render_tag_chips(tags, partials)}</slot:tags>
    <slot:date>#{escape(date)}</slot:date>
    <slot:url>#{escape(url)}</slot:url>
    <slot:title>#{escape(meta["title"])}</slot:title>
    <slot:summary>#{escape(meta["summary"])}</slot:summary>
    <%/ blog_index_item.html %>
    """

    input = %ParseInput{
      file: template,
      template_dir: template_dir,
      partials: partials,
      partial_meta: partial_meta,
      compiled_partials: compiled_partials
    }

    case Parser.parse(input) do
      {:ok, html} -> html
      _ -> ""
    end
  end

  @doc """
  Renders a list of tag names as `<a>` chips linking to `/tags/<name>`.
  Returns an empty string for an empty list.
  """
  @tag_chip_key "partials/tag_chip.html"
  @tag_chip_fallback ~s( · <a class="post-tag" href="/tags/{{tag}}" data-testid="tag-chip">{{tag}}</a>)

  @spec render_tag_chips([String.t()], map()) :: String.t()
  def render_tag_chips([], _partials), do: ""

  def render_tag_chips(tags, partials) when is_list(tags) do
    template = Map.get(partials, @tag_chip_key, @tag_chip_fallback)

    Enum.map_join(tags, "", fn tag ->
      escaped = Plug.HTML.html_escape(tag)

      template
      |> String.replace("{{tag}}", escaped)
    end)
  end

  defp normalize_tags(nil), do: []
  defp normalize_tags(tags) when is_list(tags), do: tags
  defp normalize_tags(raw) when is_binary(raw), do: FrontMatter.parse_tags(raw)

  defp escape(nil), do: ""
  defp escape(value), do: Plug.HTML.html_escape(value)
end
