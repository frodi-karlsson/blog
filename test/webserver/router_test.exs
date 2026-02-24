defmodule Webserver.RouterTest do
  use ExUnit.Case

  @moduletag :capture_log

  defp call(method, path) do
    conn = Plug.Test.conn(method, path)
    Webserver.Router.call(conn, Webserver.Router.init([]))
  end

  describe "GET /health" do
    test "returns 200 with JSON body" do
      conn = call(:get, "/health")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "application/json"
      assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
    end
  end

  describe "GET /admin/cache/stats" do
    test "returns 200 with stats JSON" do
      conn = call(:get, "/admin/cache/stats")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "hits")
      assert Map.has_key?(body, "misses")
      assert Map.has_key?(body, "revalidations")
    end
  end

  describe "POST /admin/cache/refresh" do
    test "returns 200 on success" do
      conn = call(:post, "/admin/cache/refresh")
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "cache refreshed"}
    end
  end

  describe "GET /" do
    test "forwards to Server and returns 200" do
      conn = call(:get, "/")
      assert conn.status == 200
      assert conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) =~ "text/html"
    end
  end

  describe "GET /nonexistent" do
    test "forwards to Server and returns 404" do
      conn = call(:get, "/nonexistent")
      assert conn.status == 404
    end
  end

  describe "HEAD requests" do
    test "HEAD / returns 200 with empty body" do
      conn = call(:head, "/")
      assert conn.status == 200
      assert conn.resp_body == ""
    end
  end
end
