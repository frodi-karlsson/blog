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
        # todo: indentation match and extra newline?
        output:
          {:ok,
           ~S"""
             <html>
                 <head>
               <title>Hello world</title>
             </head>

             </html>
           """}
      }
    ]

    for test_case <- @cases do
      test "should give expected output for #{test_case.name}" do
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
  end
end
