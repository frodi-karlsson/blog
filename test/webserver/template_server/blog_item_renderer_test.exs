defmodule Webserver.TemplateServer.BlogItemRendererTest do
  use ExUnit.Case, async: true

  alias Webserver.TemplateServer.BlogItemRenderer

  @partials %{
    "partials/blog_index_item.html" => ~S"""
    <article>
      <span class="tags">{{tags}}</span>
      <time>{{date}}</time>
      <a href="{{url}}">{{title}}</a>
      <p>{{summary}}</p>
    </article>
    """,
    "partials/tag_chip.html" => ~S"""
     · <a class="post-tag" href="/tags/{{tag}}" data-testid="tag-chip">{{tag}}</a>
    """
  }

  test "renders a blog item from meta" do
    meta = %{
      "title" => "Hello",
      "tags" => "typescript, anabranch",
      "date" => "2026-06-01",
      "summary" => "A summary"
    }

    html = BlogItemRenderer.render("hello.html", meta, "/priv/templates", @partials)

    assert html =~ ~s|<a href="/hello">Hello</a>|
    assert html =~ "Jun 1, 2026"
    assert html =~ "A summary"
    assert html =~ ~s|href="/tags/typescript"|
    assert html =~ ~s|href="/tags/anabranch"|
    assert html =~ ~s|data-testid="tag-chip"|
  end

  test "prefers meta path over derived filename" do
    meta = %{
      "title" => "Custom",
      "tags" => "",
      "date" => "2026-06-01",
      "summary" => "s",
      "path" => "/custom-path"
    }

    html = BlogItemRenderer.render("a.html", meta, "/priv/templates", @partials)
    assert html =~ ~s|<a href="/custom-path">Custom</a>|
  end

  test "html-escapes values" do
    meta = %{
      "title" => "<script>alert()</script>",
      "tags" => "",
      "date" => "2026-06-01",
      "summary" => "s"
    }

    html = BlogItemRenderer.render("a.html", meta, "/priv/templates", @partials)
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "accepts tags as a list (from Post.to_meta)" do
    meta = %{
      "title" => "Listy",
      "tags" => ["elixir", "beam"],
      "date" => "2026-06-01",
      "summary" => "s"
    }

    html = BlogItemRenderer.render("a.html", meta, "/priv/templates", @partials)
    assert html =~ ~s|href="/tags/elixir"|
    assert html =~ ~s|href="/tags/beam"|
  end

  test "renders no chips when tags key is missing" do
    meta = %{
      "title" => "Notags",
      "date" => "2026-06-01",
      "summary" => "s"
    }

    html = BlogItemRenderer.render("a.html", meta, "/priv/templates", @partials)
    refute html =~ ~s|data-testid="tag-chip"|
  end
end
