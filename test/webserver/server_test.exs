defmodule Webserver.ServerTest do
  use ExUnit.Case

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  describe "call" do
    @cases [
      %{
        name: "return parsed template for root path",
        path: "/",
        expected_status: 200,
        expected_body: "<html"
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
        conn = Webserver.Server.call(conn, [])

        assert conn.status == unquoted.expected_status
        assert String.contains?(conn.resp_body, unquoted.expected_body)
      end
    end

    test "returns 405 for non-GET methods" do
      conn = Plug.Test.conn(:post, "/")
      conn = Webserver.Server.call(conn, [])
      assert conn.status == 405
    end
  end

  describe "parser error handling" do
    test "returns error for missing slots" do
      partials = %{
        "partials/head.html" => "<head><title>Test</title></head>",
        "partials/page.html" => "<html><head>{{title}}</head><body>{{body}}</body></html>"
      }

      file = """
      <% page.html %>
      <slot:body>Content</slot:body>
      <%/ page.html %>
      """

      assert {:error, {:missing_slots, ["title"]}} =
               Parser.parse(%ParseInput{
                 file: file,
                 template_dir: "/test",
                 partials: partials
               })
    end

    test "returns error for unexpected slots" do
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

      assert {:error, {:unexpected_slots, ["extra"]}} =
               Parser.parse(%ParseInput{
                 file: file,
                 template_dir: "/test",
                 partials: partials
               })
    end
  end
end
