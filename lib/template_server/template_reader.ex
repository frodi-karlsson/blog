defmodule TemplateServer.TemplateReader do
  @moduledoc """
  Template reader behavior and implementations for reading templates.
  Supports both in-memory (Sandbox) and filesystem-based (File) reading.
  """
  def get_partials(base_url) do
    impl().get_partials(base_url)
  end

  def read_page(base_url, path) do
    impl().read_page(base_url, path)
  end

  def read_partial(base_url, filename) do
    impl().read_partial(base_url, filename)
  end

  defp impl do
    Application.get_env(:webserver, :template_reader)
  end
end

defmodule TemplateServer.TemplateReader.Sandbox do
  @moduledoc """
  In-memory template reader implementation for testing.
  Returns predefined templates for known paths and errors for invalid paths.
  """

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
  @moduledoc """
  File-based template reader implementation.
  Reads templates from the filesystem at the configured base_url.
  """

  require Logger

  def get_partials(base_url) do
    dir = Path.join(base_url, "partials")

    with {:ok, files} <- File.ls(dir) do
      Logger.debug(%{event: "reading_partials_dir", path: dir, file_count: length(files)})

      partials = read_partial_files(dir, files)

      Logger.info(%{event: "partials_loaded", count: map_size(partials)})
      {:ok, partials}
    end
  end

  defp read_partial_files(dir, files) do
    Enum.reduce(files, %{}, fn file, acc ->
      full = Path.join(dir, file)
      read_single_partial(full, acc)
    end)
  end

  defp read_single_partial(full, acc) do
    case File.read(full) do
      {:ok, content} ->
        key = Path.join("partials", Path.basename(full))
        Logger.debug(%{event: "partial_loaded", key: key, size: byte_size(content)})
        Map.put(acc, key, content)

      {:error, reason} ->
        Logger.warning(%{event: "partial_read_failed", path: full, reason: reason})
        acc
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
          Logger.warning(%{event: "page_read_failed", path: rel_path, reason: reason})
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
        Logger.warning(%{event: "partial_reload_failed", filename: filename, reason: reason})
        {:error, reason}
    end
  end
end
