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
    if path == "index.html" do
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
end

defmodule TemplateServer.TemplateReader.File do
  def get_partials(base_url) do
    dir = Path.join(base_url, "partials")

    with {:ok, files} <- File.ls(dir) do
      partials =
        Enum.reduce(files, %{}, fn file, acc ->
          full = Path.join(dir, file)

          case File.read(full) do
            {:ok, content} ->
              # KEY MUST MATCH RESOLVER CONTRACT
              Map.put(acc, Path.join("partials", file), content)

            _ ->
              acc
          end
        end)

      {:ok, partials}
    end
  end

  def read_page(base_url, path) do
    with {:ok, rel_path} <- Parser.Resolver.resolve_page(path, base_url) do
      full_path = Path.join(base_url, rel_path)

      case File.read(full_path) do
        {:ok, content} -> {:ok, content}
        error -> error
      end
    end
  end
end
