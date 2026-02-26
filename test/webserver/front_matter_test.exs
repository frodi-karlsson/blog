defmodule Webserver.FrontMatterTest do
  use ExUnit.Case, async: true

  alias Webserver.FrontMatter

  describe "parse/1" do
    @cases [
      %{
        name: "valid front-matter",
        input: "---\ntitle: My Post\ndate: 2026-02-25\n---\n<html/>",
        metadata: %{"title" => "My Post", "date" => "2026-02-25"},
        body: "<html/>"
      },
      %{
        name: "no front-matter",
        input: "<html/>",
        metadata: %{},
        body: "<html/>"
      },
      %{
        name: "empty front-matter block",
        input: "---\n---\n<html/>",
        metadata: %{},
        body: "<html/>"
      },
      %{
        name: "value containing a colon (URL)",
        input: "---\ncanonical: https://example.com/foo\n---\nbody",
        metadata: %{"canonical" => "https://example.com/foo"},
        body: "body"
      },
      %{
        name: "noindex flag",
        input: "---\nnoindex: true\n---\nbody",
        metadata: %{"noindex" => "true"},
        body: "body"
      },
      %{
        name: "multiline body preserved",
        input: "---\ntitle: Test\n---\nline1\nline2\nline3",
        metadata: %{"title" => "Test"},
        body: "line1\nline2\nline3"
      },
      %{
        name: "single dash prefix is not treated as front-matter",
        input: "--\ntitle: Test\n--\nbody",
        metadata: %{},
        body: "--\ntitle: Test\n--\nbody"
      },
      %{
        name: "lines without colon-space separator are ignored",
        input: "---\ntitle: Valid\ninvalid-line\n---\nbody",
        metadata: %{"title" => "Valid"},
        body: "body"
      }
    ]

    for tc <- @cases do
      test "#{tc.name}" do
        tc = unquote(Macro.escape(tc))
        {meta, body} = FrontMatter.parse(tc.input)
        assert meta == tc.metadata
        assert body == tc.body
      end
    end
  end

  describe "blog_post?/1" do
    test "returns true when date and summary present" do
      assert FrontMatter.blog_post?(%{"date" => "2026-02-25", "summary" => "A summary"})
    end

    test "returns false when only date present" do
      refute FrontMatter.blog_post?(%{"date" => "2026-02-25"})
    end

    test "returns false when only summary present" do
      refute FrontMatter.blog_post?(%{"summary" => "A summary"})
    end

    test "returns false for empty metadata" do
      refute FrontMatter.blog_post?(%{})
    end
  end

  describe "format_date/1" do
    @cases [
      %{input: "2026-02-25", output: "Feb 25, 2026"},
      %{input: "2024-01-01", output: "Jan 1, 2024"},
      %{input: "2025-12-31", output: "Dec 31, 2025"},
      %{input: "2024-03-07", output: "Mar 7, 2024"}
    ]

    for tc <- @cases do
      test "formats #{tc.input}" do
        tc = unquote(Macro.escape(tc))
        assert FrontMatter.format_date(tc.input) == tc.output
      end
    end

    test "returns original string for invalid date" do
      assert FrontMatter.format_date("not-a-date") == "not-a-date"
    end
  end

  describe "derive_path/1" do
    @cases [
      %{input: "index.html", output: "/"},
      %{input: "my-post.html", output: "/my-post"},
      %{input: "admin/design-system.html", output: "/admin/design-system"},
      %{
        input: "building-an-elixir-webserver-from-scratch.html",
        output: "/building-an-elixir-webserver-from-scratch"
      },
      %{input: "blog/index.html", output: "/blog"}
    ]

    for tc <- @cases do
      test "derives path from #{tc.input}" do
        tc = unquote(Macro.escape(tc))
        assert FrontMatter.derive_path(tc.input) == tc.output
      end
    end
  end
end
