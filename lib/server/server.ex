defmodule Server do
  @moduledoc """
  A web server that returns parsed templates
  """
  @behaviour Plug
  import Plug.Conn
  require Logger

  def init(opts) do
    opts
  end

  @doc """
  Responds with a 200 + html file, or error code + plain text
  """
  def call(conn, _opts) do
    path = request_path(conn)

    Logger.info(%{
      event: "request_received",
      method: conn.method,
      path: path,
      request_id: conn.assigns[:request_id]
    })

    case TemplateServer.Cache.get_page(path) do
      {:ok, parsed} ->
        Logger.info(%{event: "request_completed", path: path, status: 200})

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, parsed)

      {:error, :not_found} ->
        Logger.info(%{event: "page_not_found", path: path})

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          404,
          error_html(404, "Page Not Found", "The requested page could not be found.")
        )

      {:error, _reason} ->
        Logger.error(%{event: "server_error", path: path})

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          500,
          error_html(
            500,
            "Internal Server Error",
            "An error occurred while processing your request."
          )
        )
    end
  end

  defp request_path(conn) do
    case conn.request_path do
      "/" -> "index.html"
      p -> p |> String.trim_leading("/") |> Kernel.<>(".html")
    end
  end

  defp error_html(code, title, message) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>#{code} #{title}</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                background: #f5f5f5;
                color: #333;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
            }
            .container {
                background: white;
                padding: 2rem;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                text-align: center;
                max-width: 500px;
            }
            h1 { font-size: 1.5rem; margin-bottom: 1rem; color: #{error_color(code)}; }
            p { color: #666; line-height: 1.6; }
            code { background: #f0f0f0; padding: 0.2rem 0.4rem; border-radius: 4px; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>#{code} #{title}</h1>
            <p>#{message}</p>
        </div>
    </body>
    </html>
    """
  end

  defp error_color(404), do: "#e67e22"
  defp error_color(_), do: "#e74c3c"
end
