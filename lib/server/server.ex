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

    base_url = Application.get_env(:webserver, :base_url)

    case Webserver.start_template_server(base_url) do
      {:ok, template_server} ->
        Logger.debug(%{event: "template_server_started", pid: inspect(template_server)})

        partials = TemplateServer.get_partials(template_server)
        GenServer.stop(template_server)

        file_path = path_to_file(path)

        Logger.debug(%{event: "template_loading", path: file_path})

        case parse_for_request(base_url, file_path, partials) do
          {:ok, parsed} ->
            Logger.info(%{event: "request_completed", path: path, status: 200})

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(200, parsed)

          {:error, {:ref_not_found, _}} ->
            Logger.info(%{event: "page_not_found", path: file_path})

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              404,
              error_html(404, "Page Not Found", "The requested page could not be found.")
            )

          {:error, {:missing_slots, slots}} ->
            Logger.error(%{event: "parse_error", path: file_path, missing_slots: slots})

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              500,
              error_html(
                500,
                "Template Error",
                "Missing required slots: #{Enum.join(slots, ", ")}"
              )
            )

          {:error, {:unexpected_slots, slots}} ->
            Logger.error(%{event: "parse_error", path: file_path, unexpected_slots: slots})

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              500,
              error_html(500, "Template Error", "Unexpected slots: #{Enum.join(slots, ", ")}")
            )

          {:error, {:not_found, _}} ->
            Logger.warning("template_not_found", path: file_path)

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              404,
              error_html(404, "Page Not Found", "The requested page could not be found.")
            )

          {:error, :enoent} ->
            Logger.warning("template_not_found", path: file_path)

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(
              404,
              error_html(404, "Page Not Found", "The requested page could not be found.")
            )

          {:error, reason} ->
            Logger.error(%{event: "parse_error", path: file_path, reason: reason})

            conn
            |> put_resp_content_type("text/html")
            |> send_resp(500, error_html(500, "Server Error", "An internal error occurred."))
        end

      {:error, reason} ->
        Logger.error(%{event: "template_server_failed", reason: reason})

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          500,
          error_html(500, "Server Error", "Failed to initialize template server.")
        )
    end
  end

  defp request_path(conn) do
    case conn.request_path do
      "/" -> "index.html"
      p -> p |> String.trim_leading("/") |> Kernel.<>(".html")
    end
  end

  defp path_to_file("index.html"), do: "index.html"
  defp path_to_file(path) when is_binary(path), do: path

  defp parse_for_request(base_url, request_path, partials) do
    with {:ok, file} <- TemplateServer.TemplateReader.read_page(base_url, request_path) do
      Logger.debug(%{
        event: "template_parsing",
        path: request_path,
        partial_count: map_size(partials)
      })

      Parser.parse(%Parser.ParseInput{
        file: file,
        base_url: base_url,
        partials: partials
      })
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
