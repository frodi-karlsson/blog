defmodule ServerTest do
  use ExUnit.Case
  doctest(Server)

  describe "call" do
    @cases [
      %{
        name: "return parsed template for root path",
        path: "/",
        expected_status: 200,
        expected_body:
          "<html>\n  <head>\n  <title>Hello world</title>\n</head>\n\n  <body>\n  </body>\n</html>\n"
      },
      %{
        name: "return 404 for missing template",
        path: "/nonexistent",
        expected_status: 404,
        expected_body: "<h1>404 Page Not Found</h1>"
      }
    ]

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted = unquote(Macro.escape(test_case))

        conn = Plug.Test.conn(:get, unquoted.path)
        conn = Server.call(conn, [])

        assert conn.status == unquoted.expected_status
        assert String.contains?(conn.resp_body, unquoted.expected_body)
      end
    end
  end

  describe "parser error handling" do
    test "returns 500 for missing slots" do
      partials = %{
        "partials/head.html" => "<head><title>Test</title></head>",
        "partials/page.html" => "<html><head>{{title}}</head><body>{{body}}</body></html>"
      }

      file = """
      <% page.html %>
      <slot:body>Content</slot:body>
      <%/ page.html %>
      """

      {:error, {:missing_slots, ["title"]}} =
        Parser.parse(%Parser.ParseInput{
          file: file,
          base_url: "/test",
          partials: partials
        })
    end

    test "returns 500 for unexpected slots" do
      partials = %{
        "partials/head.html" => "<head><title>Test</title></head>",
        "partials/page.html" => "<html><head>{{title}}</head><body>{{body}}</body></html>"
      }

      file = """
      <% page.html %>
      <slot:title>Title</slot:title>
      <slot:body>Body</slot:body>
      <slot:extra>Extra</slot:extra>
      <%/ page.html %>
      """

      {:error, {:unexpected_slots, ["extra"]}} =
        Parser.parse(%Parser.ParseInput{
          file: file,
          base_url: "/test",
          partials: partials
        })
    end
  end
end
