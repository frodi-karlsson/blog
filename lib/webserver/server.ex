defmodule Webserver.Server do
  @moduledoc """
  Plug that resolves request paths to parsed HTML templates via the cache.
  Returns 200 on success, 404 for missing pages, 405 for non-GET methods,
  503 if the cache is unavailable, and 500 for all other errors.
  """

  @behaviour Plug

  import Plug.Conn

  alias Webserver.TemplateServer.Cache

  require Logger

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: method} = conn, _opts) when method not in ["GET", "HEAD"] do
    send_resp(conn, 405, "Method Not Allowed")
  end

  def call(conn, _opts) do
    path = request_path(conn)

    result = try_get_page(path)

    case result do
      {:ok, parsed} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, parsed)

      {:error, :not_found} ->
        case Cache.get_page("404.html") do
          {:ok, error_parsed} ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(404, error_parsed)

          _ ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              404,
              error_html(404, "Page Not Found", "The requested page could not be found.")
            )
        end

      {:error, :cache_unavailable} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          503,
          error_html(
            503,
            "Service Unavailable",
            "The server is temporarily unavailable. Please try again shortly."
          )
        )

      {:error, reason} ->
        Logger.error(%{event: "request_failed", path: request_path(conn), reason: reason})

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

  defp try_get_page(path) do
    case Cache.get_page(path) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} when reason in [:not_found, :eisdir] ->
        maybe_try_index(path)

      error ->
        error
    end
  rescue
    ArgumentError -> {:error, :cache_unavailable}
  catch
    :exit, _ -> {:error, :cache_unavailable}
  end

  defp maybe_try_index(path) do
    if String.ends_with?(path, "index.html") do
      {:error, :not_found}
    else
      alt_path = path |> String.replace_trailing(".html", "") |> Path.join("index.html")
      Cache.get_page(alt_path)
    end
  end

  defp request_path(%Plug.Conn{request_path: "/"}), do: "index.html"

  defp request_path(%Plug.Conn{request_path: path}) do
    path = String.trim_leading(path, "/")

    if String.ends_with?(path, "/") or path == "" do
      path <> "index.html"
    else
      path <> ".html"
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
                background: #110f0e;
                color: #fafaf9;
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
            }
            .container {
                background: #1c1917;
                padding: 2rem;
                border-radius: 8px;
                box-shadow: 0 4px 10px rgba(0,0,0,0.3);
                text-align: center;
                max-width: 500px;
                border: 1px solid #292524;
            }
            h1 { font-size: 1.5rem; margin-bottom: 1rem; color: #{error_color(code)}; }
            p { color: #a8a29e; line-height: 1.6; }
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

  defp error_color(404), do: "#fb923c"
  defp error_color(503), do: "#38bdf8"
  defp error_color(_), do: "#f87171"
end
