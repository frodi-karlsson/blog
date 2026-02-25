defmodule Webserver.SitemapTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias Webserver.Sitemap

  test "should return XML with expected locations on GET /sitemap.xml" do
    conn = conn(:get, "/sitemap.xml")
    conn = Sitemap.call(conn, Sitemap.init([]))

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]

    body = conn.resp_body
    assert body =~ "<urlset"
    assert body =~ "<loc>https://blog.frodikarlsson.com/</loc>"

    assert body =~
             "<loc>https://blog.frodikarlsson.com/building-an-elixir-webserver-from-scratch</loc>"
  end
end
