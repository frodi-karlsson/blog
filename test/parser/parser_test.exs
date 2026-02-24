defmodule ParserTest do
  use ExUnit.Case

  describe "parse" do
    @cases [
      %{
        name: "simple head interpolation",
        input: ~S"""
          <html>
            <% head.html %/>
          </html>
        """,
        partials: %{
          "partials/head.html" => ~S"""
            <head>
              <title>Hello world</title>
            </head>
          """
        },
        base_url: "/priv/templates",
        output:
          {:ok,
           ~S"""
             <html>
                 <head>
               <title>Hello world</title>
             </head>

             </html>
           """}
      },
      %{
        name: "no partials in file",
        input: ~S"""
          <html>
            <body>Hello World</body>
          </html>
        """,
        partials: %{},
        base_url: "/priv/templates",
        output:
          {:ok,
           ~S"""
             <html>
               <body>Hello World</body>
             </html>
           """}
      },
      %{
        name: "partial not found returns error",
        input: ~S"""
          <html>
            <% missing.html %/>
          </html>
        """,
        partials: %{},
        base_url: "/priv/templates",
        output: {:error, {:ref_not_found, " missing.html "}}
      },
      # Old tests - now using named slot syntax
      %{
        name: "render partial with slot",
        input:
          "<html><% card.html %><slot:default>Hello World</slot:default><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{default}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>Hello World</div></html>"}
      },
      %{
        name: "render slot with nested partials",
        input: "<% card.html %><slot:default><% head.html %/></slot:default><%/ card.html %>",
        partials: %{
          "partials/card.html" => "<div>{{default}}</div>",
          "partials/head.html" => "<head><title>Test</title></head>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<div><head><title>Test</title></head></div>"}
      },
      %{
        name: "render slot with multi-line content",
        input:
          "<html><% card.html %><slot:default>Line 1\nLine 2\nLine 3</slot:default><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>\n{{default}}\n</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>\nLine 1\nLine 2\nLine 3\n</div></html>"}
      },
      %{
        name: "render multiple slots in same file",
        input:
          "<html><% card.html %><slot:default>First</slot:default><%/ card.html %><% card.html %><slot:default>Second</slot:default><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{default}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>First</div><div>Second</div></html>"}
      },
      %{
        name: "mix self-closing and slotted partials",
        input:
          "<html><% head.html %/><% card.html %><slot:default>Hello</slot:default><%/ card.html %></html>",
        partials: %{
          "partials/head.html" => "<head/>",
          "partials/card.html" => "<div>{{default}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><head/><div>Hello</div></html>"}
      },
      # Named slots tests
      %{
        name: "render named slot",
        input: "<html><% card.html %><slot:body>Content</slot:body><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div><div>{{body}}</div></div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div><div>Content</div></div></html>"}
      },
      %{
        name: "render multiple named slots",
        input:
          "<html><% layout.html %><slot:header>Header</slot:header><slot:body>Body</slot:body><%/ layout.html %></html>",
        partials: %{
          "partials/layout.html" => "<div>{{header}}{{body}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>HeaderBody</div></html>"}
      },
      %{
        name: "process nested partials in slot content before injecting into parent",
        input:
          "<html><% site.html %><slot:header><% logo.html %/></slot:header><%/ site.html %></html>",
        partials: %{
          "partials/site.html" => "<div>{{header}}</div>",
          "partials/logo.html" => "<span>Logo</span>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div><span>Logo</span></div></html>"}
      },
      %{
        name: "slots in slot content are processed before parent slot",
        input:
          "<% outer.html %><slot:inner><% inner.html %><slot:deep>Deep</slot:deep><%/ inner.html %></slot:inner><%/ outer.html %>",
        partials: %{
          "partials/outer.html" => "<outer>{{inner}}</outer>",
          "partials/inner.html" => "<inner>{{deep}}</inner>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<outer><inner>Deep</inner></outer>"}
      },
      %{
        name: "error when named slot not provided",
        input: "<html><% card.html %><slot:title>Title</slot:title><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{header}}{{body}}</div>"
        },
        base_url: "/priv/templates",
        output: {:error, {:missing_slots, ["body", "header"]}}
      },
      %{
        name: "error when slot provided but partial doesn't expect it",
        input: "<html><% card.html %><slot:header>Header</slot:header><%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{body}}</div>"
        },
        base_url: "/priv/templates",
        output: {:error, {:missing_slots, ["body"]}}
      }
    ]

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted_test_case = unquote(Macro.escape(test_case))

        result =
          Parser.parse(%Parser.ParseInput{
            file: unquoted_test_case.input,
            partials: unquoted_test_case.partials,
            base_url: unquoted_test_case.base_url
          })

        assert result == unquoted_test_case.output
      end
    end

    test "should handle empty file" do
      result =
        Parser.parse(%Parser.ParseInput{
          file: "",
          partials: %{},
          base_url: "/priv/templates"
        })

      assert result == {:ok, ""}
    end
  end
end
