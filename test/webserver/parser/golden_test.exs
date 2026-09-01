defmodule Webserver.Parser.GoldenTest do
  @moduledoc """
  Renders every real page through the real templates and asserts structural
  invariants. Guards against a parser change that silently stops resolving
  nested partials or leaves placeholders unsubstituted.
  """
  use ExUnit.Case, async: false

  alias Webserver.Content.Query
  alias Webserver.Content.Store
  alias Webserver.Content.TemplateReader.File, as: FileReader

  setup_all do
    name = :"golden_#{System.unique_integer([:positive])}"
    # Application config's :template_dir is the Sandbox reader's magic key
    # ("/priv/templates"), not a real filesystem path. The real templates
    # live under priv/templates relative to the app's priv dir.
    template_dir = Path.join(:code.priv_dir(:webserver), "templates")

    {:ok, _pid} =
      GenServer.start_link(Store, {template_dir, 0, FileReader, false, name}, name: name)

    {:ok, name: name}
  end

  defp render_all(name) do
    for %{"path" => path} <- Query.get_sitemap(name) do
      file = String.trim_leading(path, "/")
      file = if file == "", do: "index", else: file
      {:ok, html} = Store.get_page(name, file <> ".html")
      {path, html}
    end
  end

  test "every page renders", %{name: name} do
    pages = render_all(name)
    assert length(pages) >= 6, "expected the real page set, got #{length(pages)}"
  end

  test "every page is a complete document", %{name: name} do
    for {path, html} <- render_all(name) do
      assert html =~ "<html", "#{path} is missing <html"
      assert html =~ "</html>", "#{path} is missing </html>"
      assert html =~ "<body", "#{path} is missing <body"
    end
  end

  # Strips <code>/<pre> content before scanning for leaked placeholders. At
  # least one post documents the templating syntax itself and legitimately
  # contains literal text like `{{name}}` inside a <code> span -- that is
  # prose, not a rendering defect, and stripping it keeps this check honest
  # about genuine leaks (which land outside markup, not inside it).
  defp strip_code_blocks(html) do
    Regex.replace(~r/<(code|pre)\b[^>]*>.*?<\/\1>/s, html, "")
  end

  test "no page leaks an unsubstituted placeholder", %{name: name} do
    for {path, html} <- render_all(name) do
      scrubbed = strip_code_blocks(html)
      refute scrubbed =~ ~r/\{\{[a-z_@+]/, "#{path} contains an unsubstituted placeholder"
      refute scrubbed =~ "<% ", "#{path} contains an unresolved template tag"
    end
  end

  test "nested partials are resolved", %{name: name} do
    # header_assets.html is referenced from inside layout.html, so its content
    # only appears if partial-inside-partial resolution works. This is the exact
    # invariant an AST rewrite is most likely to break.
    #
    # This must check for something layout.html does NOT itself emit --
    # layout.html has its own `<link rel="canonical">`, so a bare `<link`
    # check passes even when header_assets.html fails to render, which was
    # verified against a deliberate mutation of render_partial_with_slots_and_attrs/4
    # that stopped resolving nested tags. rel="stylesheet" and rel="icon" only
    # come from header_assets.html.
    for {path, html} <- render_all(name) do
      assert html =~ ~s|rel="stylesheet"|,
             "#{path} has no stylesheet <link> -- header_assets.html did not render"

      assert html =~ ~s|rel="icon"|,
             "#{path} has no icon <link> -- header_assets.html did not render"
    end
  end

  test "asset placeholders are resolved", %{name: name} do
    for {path, html} <- render_all(name) do
      refute html =~ "{{+", "#{path} contains an unresolved asset placeholder"
    end
  end
end
