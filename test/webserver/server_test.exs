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

    test "should return 405 for non-GET methods" do
      conn = Plug.Test.conn(:post, "/")
      conn = Webserver.Server.call(conn, [])
      assert conn.status == 405
    end
  end

  describe "GET /?q=" do
    defp build_search_conn(path) do
      Plug.Test.conn(:get, path)
      |> Webserver.Router.call(Webserver.Router.init([]))
    end

    test "with a non-empty query, returns filtered results" do
      conn = build_search_conn("/?q=post+a")
      assert conn.status == 200
      assert conn.resp_body =~ "Results for"
      assert conn.resp_body =~ "post-a"
      refute conn.resp_body =~ "post-b"
    end

    test "with an empty query, falls through to the normal index" do
      conn = build_search_conn("/?q=")
      assert conn.status == 200
      refute conn.resp_body =~ "Results for"
    end

    test "html-escapes the echoed query" do
      conn = build_search_conn("/?q=%3Cscript%3E")
      assert conn.status == 200
      refute conn.resp_body =~ "<script>"
      assert conn.resp_body =~ "&lt;script&gt;"
    end

    test "empty result renders an empty state" do
      conn = build_search_conn("/?q=zzz-no-such-post")
      assert conn.status == 200
      assert conn.resp_body =~ "No posts matching"
      assert conn.resp_body =~ ~s|href="/tags"|
    end

    test "truncates very long queries without crashing" do
      long = String.duplicate("a", 500)
      conn = build_search_conn("/?q=" <> long)
      assert conn.status == 200
    end

    test "query containing {{ ... }} still renders without triggering asset parser" do
      conn = build_search_conn("/?q=%7B%7B%2B%2Ffoo%7D%7D")
      assert conn.status == 200
      refute conn.resp_body =~ "Search unavailable"
    end
  end

  describe "parser error handling" do
    test "should return error for missing slots" do
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

    test "should return error for unexpected slots" do
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
