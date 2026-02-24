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
        expected_body: "Template not found"
      }
    ]

    setup do
      Application.put_env(:webserver, :base_url, "/priv/templates")
      :ok
    end

    for test_case <- @cases do
      test "should #{test_case.name}" do
        unquoted = unquote(Macro.escape(test_case))

        conn = Plug.Test.conn(:get, unquoted.path)
        conn = Server.call(conn, [])

        assert conn.status == unquoted.expected_status
        assert conn.resp_body == unquoted.expected_body
      end
    end
  end
end
