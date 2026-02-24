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

    with {:ok, template_server} <- Webserver.start_template_server(base_url) do
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

        {:error, reason} ->
          Logger.warning("template_not_found", path: file_path, reason: reason)

          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(404, "Template not found")
      end
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
end
