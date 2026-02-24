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
      %{
        name: "render partial with slot",
        input: "<html><% card.html %>Hello World<%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{slot}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>Hello World</div></html>"}
      },
      %{
        name: "render slot with nested partials",
        input: "<% card.html %><% head.html %/><%/ card.html %>",
        partials: %{
          "partials/card.html" => "<div>{{slot}}</div>",
          "partials/head.html" => "<head><title>Test</title></head>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<div><head><title>Test</title></head></div>"}
      },
      %{
        name: "render slot with multi-line content",
        input: "<html><% card.html %>Line 1\nLine 2\nLine 3<%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>\n{{slot}}\n</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>\nLine 1\nLine 2\nLine 3\n</div></html>"}
      },
      %{
        name: "render multiple slots in same file",
        input:
          "<html><% card.html %>First<%/ card.html %><% card.html %>Second<%/ card.html %></html>",
        partials: %{
          "partials/card.html" => "<div>{{slot}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><div>First</div><div>Second</div></html>"}
      },
      %{
        name: "render nested slots",
        input: "<% outer.html %><% inner.html %>content<%/ inner.html %><%/ outer.html %>",
        partials: %{
          "partials/outer.html" => "<outer>{{slot}}</outer>",
          "partials/inner.html" => "<inner>{{slot}}</inner>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<outer><inner>content</inner></outer>"}
      },
      %{
        name: "mix self-closing and slotted partials",
        input: "<html><% head.html %/><% card.html %>Hello<%/ card.html %></html>",
        partials: %{
          "partials/head.html" => "<head/>",
          "partials/card.html" => "<div>{{slot}}</div>"
        },
        base_url: "/priv/templates",
        output: {:ok, "<html><head/><div>Hello</div></html>"}
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
