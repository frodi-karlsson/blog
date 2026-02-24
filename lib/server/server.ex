defmodule Server do
  @moduledoc """
  A web server that returns parsed templates
  """
  @behaviour Plug
  import Plug.Conn

  def init(opts) do
    opts
  end

  @doc """
  Responds with a 200 + html file, or error code + plain text
  """
  def call(conn, _opts) do
    base_url = Application.get_env(:webserver, :base_url)

    case Webserver.start_template_server(base_url) do
      {:ok, template_server} ->
        partials = TemplateServer.get_partials(template_server)
        GenServer.stop(template_server)

        path =
          case conn.request_path do
            "/" -> "index.html"
            p -> p |> String.trim_leading("/") |> Kernel.<>(".html")
          end

        case parse_for_request(base_url, path, partials) do
          {:ok, parsed} ->
            conn
            |> put_resp_content_type("text/html")
            |> send_resp(200, parsed)

          {:error, _reason} ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(404, "Template not found")
        end
    end
  end

  defp parse_for_request(base_url, request_path, partials) do
    with {:ok, file} <- TemplateServer.TemplateReader.read_page(base_url, request_path) do
      Parser.parse(%Parser.ParseInput{
        file: file,
        base_url: Application.get_env(:webserver, :base_url),
        partials: partials
      })
    end
  end
end
