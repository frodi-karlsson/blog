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
