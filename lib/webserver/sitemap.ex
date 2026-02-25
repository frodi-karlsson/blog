defmodule Webserver.Sitemap do
  @moduledoc """
  Plug that generates an XML sitemap based on the page registry.
  """
  @behaviour Plug
  import Plug.Conn

  alias Webserver.TemplateServer.Cache

  def init(opts), do: opts

  def call(conn, _opts) do
    pages = Cache.get_sitemap()
    base_url = Application.get_env(:webserver, :external_url, "https://example.com")

    xml =
      ~s|<?xml version="1.0" encoding="UTF-8"?>
| <>
        ~s|<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
| <>
        Enum.map_join(pages, "\n", fn page ->
          path = Plug.HTML.html_escape(page["path"])
          "  <url><loc>#{base_url}#{path}</loc></url>"
        end) <>
        ~s|
</urlset>|

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
