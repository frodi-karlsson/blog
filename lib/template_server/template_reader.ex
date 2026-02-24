defmodule TemplateServer.TemplateReader do
  @doc """
  Fetches all partials from the templates directory

  ## Examples

  iex> {:ok, partials} = TemplateServer.TemplateReader.get_partials("/priv/templates")
  iex> partials["partials/head.html"]
  "<head>\n  <title>Hello world</title>\n</head>\n"
  """
  def get_partials(base_url) do
    impl().get_partials(base_url)
  end

  @doc """
  Reads a single page from the templates directory

  ## Examples

  iex> TemplateServer.TemplateReader.read_page("/priv/templates", "index.html")
  {:ok, \"<html>\n  <% head.html %/>\n  <body>\n  </body>\n</html>\n\"}
  """
  def read_page(base_url, path) do
    impl().read_page(base_url, path)
  end

  @doc """
  Reads a single partial file by filename

  ## Examples

  iex> TemplateServer.TemplateReader.read_partial("/priv/templates", "head.html")
  {:ok, "<head>...</head>"}
  """
  def read_partial(base_url, filename) do
    impl().read_partial(base_url, filename)
  end

  defp impl do
    Application.get_env(:webserver, :template_reader)
  end
end

defmodule TemplateServer.TemplateReader.Sandbox do
  def get_partials(base_url) do
    if base_url == "/priv/templates" do
      {:ok,
       %{
         "partials/head.html" => ~S"""
         <head>
           <title>Hello world</title>
         </head>
         """,
         "partials/blog.html" => ~S"""
         <div class="blog">
           <h1 class="title">
           <p class="body">
         </div>
         """
       }}
    else
      {:error, {:enoent}}
    end
  end

  def read_page(_base_url, path) do
    if String.ends_with?(path, "index.html") do
      {:ok,
       ~S"""
       <html>
         <% head.html %/>
         <body>
         </body>
       </html>
       """}
    else
      {:error, {:not_found, path}}
    end
  end

  def read_partial(_base_url, "head.html") do
    {:ok, "<head>...</head>"}
  end

  def read_partial(_base_url, filename) when is_binary(filename) do
    {:ok, "<partial>#{filename}</partial>"}
  end
end

defmodule TemplateServer.TemplateReader.File do
  require Logger

  def get_partials(base_url) do
    dir = Path.join(base_url, "partials")

    with {:ok, files} <- File.ls(dir) do
      Logger.debug(%{event: "reading_partials_dir", path: dir, file_count: length(files)})

      partials =
        Enum.reduce(files, %{}, fn file, acc ->
          full = Path.join(dir, file)

          case File.read(full) do
            {:ok, content} ->
              key = Path.join("partials", file)
              Logger.debug(%{event: "partial_loaded", key: key, size: byte_size(content)})
              Map.put(acc, key, content)

            {:error, reason} ->
              Logger.warning("partial_read_failed", path: full, reason: reason)
              acc
          end
        end)

      Logger.info(%{event: "partials_loaded", count: map_size(partials)})
      {:ok, partials}
    end
  end

  def read_page(base_url, path) do
    with {:ok, rel_path} <- Parser.Resolver.resolve_page(path, base_url) do
      full_path = Path.join(base_url, rel_path)

      case File.read(full_path) do
        {:ok, content} ->
          Logger.debug(%{event: "page_loaded", path: rel_path, size: byte_size(content)})
          {:ok, content}

        {:error, reason} ->
          Logger.warning("page_read_failed", path: rel_path, reason: reason)
          {:error, reason}
      end
    end
  end

  def read_partial(base_url, filename) do
    full_path = Path.join([base_url, "partials", filename])

    case File.read(full_path) do
      {:ok, content} ->
        Logger.debug(%{event: "partial_reloaded", filename: filename, size: byte_size(content)})
        {:ok, content}

      {:error, reason} ->
        Logger.warning("partial_reload_failed", filename: filename, reason: reason)
        {:error, reason}
    end
  end
end
