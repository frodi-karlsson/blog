defmodule Webserver.ParserResolverTest do
  use ExUnit.Case
  doctest(Webserver.Parser.Resolver)

  alias Webserver.Parser.ParseInput
  alias Webserver.Parser.Resolver

  describe "resolve_partial_reference" do
    @cases [
      %{
        name: "resolves partial reference with leading space",
        input: " head.html",
        parse_input: %ParseInput{
          partials: %{"partials/head.html" => "hello world"},
          base_url: "/priv/templates",
          file: "index.html"
        },
        expected: "hello world"
      },
      %{
        name: "returns nil when partial not found",
        input: " missing.html",
        parse_input: %ParseInput{
          partials: %{},
          base_url: "",
          file: "index.html"
        },
        expected: nil
      },
      %{
        name: "trims whitespace from reference",
        input: "  head.html  ",
        parse_input: %ParseInput{
          partials: %{"partials/head.html" => "content"},
          base_url: "/priv/templates",
          file: "index.html"
        },
        expected: "content"
      }
    ]

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted = unquote(Macro.escape(test_case))

        assert Resolver.resolve_partial_reference(unquoted.input, unquoted.parse_input) ==
                 unquoted.expected
      end
    end
  end

  describe "resolve_page" do
    @cases [
      %{
        name: "resolve page path correctly",
        input: " index.html",
        base_url: "/priv/templates",
        expected: {:ok, "pages/index.html"}
      },
      %{
        name: "handle nested paths",
        input: " about.html",
        base_url: "/priv/templates",
        expected: {:ok, "pages/about.html"}
      }
    ]

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted = unquote(Macro.escape(test_case))
        assert Resolver.resolve_page(unquoted.input, unquoted.base_url) == unquoted.expected
      end
    end
  end

  describe "resolve_path" do
    @cases [
      %{
        name: "join paths correctly",
        rel_paths: ["partials", "head.html"],
        base_dir: "/priv/templates",
        expected: {:ok, "partials/head.html"}
      },
      %{
        name: "handle relative paths",
        rel_paths: ["./file.html"],
        base_dir: "/priv/templates",
        expected: {:ok, "file.html"}
      },
      %{
        name: "reject paths with directory traversal",
        rel_paths: ["../etc/passwd"],
        base_dir: "/priv/templates",
        expected: :error
      }
    ]

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted = unquote(Macro.escape(test_case))
        assert Resolver.resolve_path(unquoted.rel_paths, unquoted.base_dir) == unquoted.expected
      end
    end
  end
end
