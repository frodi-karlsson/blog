defmodule Webserver.RouterTest do
  use ExUnit.Case
  import Plug.Conn

  @moduletag :capture_log

  defp call(method, path) do
    conn = Plug.Test.conn(method, path)

    conn =
      if String.starts_with?(path, "/admin") do
        username = Application.get_env(:webserver, :admin_username, "admin")
        password = Application.get_env(:webserver, :admin_password, "admin")

        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Basic " <> Base.encode64("#{username}:#{password}")
        )
      else
        conn
      end

    Webserver.Router.call(conn, Webserver.Router.init([]))
  end

  describe "GET /health" do
    test "should return 200 with JSON body" do
      conn = call(:get, "/health")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "application/json"
      assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
    end
  end

  describe "GET /robots.txt" do
    test "should return 200 with plain text" do
      conn = call(:get, "/robots.txt")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "text/plain"
      assert conn.resp_body =~ "User-agent: *"
      assert conn.resp_body =~ "Sitemap: https://blog.frodikarlsson.com/sitemap.xml"
    end
  end

  describe "GET /admin/cache/stats" do
    test "should return 200 with stats JSON" do
      conn = call(:get, "/admin/cache/stats")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "hits")
      assert Map.has_key?(body, "misses")
      assert Map.has_key?(body, "revalidations")
    end
  end

  describe "POST /admin/cache/refresh" do
    test "should return 200 on success" do
      conn = call(:post, "/admin/cache/refresh")
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "cache refreshed"}
    end
  end

  describe "GET /" do
    test "should forward to Server and return 200" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "text/html"
    end
  end

  describe "GET /nonexistent" do
    test "should forward to Server and return 404" do
      conn = call(:get, "/nonexistent")
      assert conn.status == 404
    end
  end

  describe "Directory index resolution" do
    test "should resolve /bespoke-elixir-web-framework to bespoke-elixir-web-framework.html" do
      conn = call(:get, "/bespoke-elixir-web-framework")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "text/html"
    end
  end

  describe "Redirects" do
    test "should redirect /building-an-elixir-webserver-from-scratch to /bespoke-elixir-web-framework" do
      conn = call(:get, "/building-an-elixir-webserver-from-scratch")
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/bespoke-elixir-web-framework"]
    end
  end

  describe "HEAD requests" do
    test "should return 200 with empty body on HEAD /" do
      conn = call(:head, "/")
      assert conn.status == 200
      assert conn.resp_body == ""
    end
  end
end
