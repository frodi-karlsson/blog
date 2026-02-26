defmodule Webserver.TemplateServer.TemplateReader.File do
  @moduledoc """
  Filesystem-based template reader. Reads templates from the directory
  configured as `template_dir`. Used in dev and prod environments.
  """

  @behaviour Webserver.TemplateServer.TemplateReader

  alias Webserver.Parser.Resolver

  require Logger

  @impl true
  def get_partials(template_dir) do
    dir = Path.join(template_dir, "partials")

    with {:ok, files} <- File.ls(dir) do
      Logger.debug(%{event: "reading_partials_dir", path: dir, file_count: length(files)})
      partials = read_partial_files(dir, files)
      Logger.info(%{event: "partials_loaded", count: map_size(partials)})
      {:ok, partials}
    end
  end

  @impl true
  def read_page(template_dir, path) do
    with {:ok, rel_path} <- Resolver.resolve_page(path, template_dir),
         {:ok, content} <- File.read(Path.join(template_dir, rel_path)) do
      Logger.debug(%{event: "page_loaded", path: rel_path, size: byte_size(content)})
      {:ok, content}
    else
      {:error, reason} when reason in [:enoent, :not_found] ->
        Logger.warning(%{event: "page_read_failed", path: path, reason: :not_found})
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning(%{event: "page_read_failed", path: path, reason: reason})
        {:error, reason}
    end
  end

  @impl true
  def list_pages(template_dir) do
    pages_dir = Path.join(template_dir, "pages")

    case do_list_pages(pages_dir, pages_dir) do
      {:error, reason} -> {:error, reason}
      files -> {:ok, files}
    end
  end

  defp do_list_pages(dir, base_dir) do
    case File.ls(dir) do
      {:ok, entries} -> Enum.flat_map(entries, &list_entry(Path.join(dir, &1), base_dir))
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_entry(full, base_dir) do
    cond do
      File.dir?(full) -> do_list_pages(full, base_dir)
      String.ends_with?(full, ".html") -> [Path.relative_to(full, base_dir)]
      true -> []
    end
  end

  @impl true
  def file_mtime(template_dir, relative_path) do
    case File.stat(Path.join([template_dir, relative_path])) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp read_partial_files(dir, files) do
    Enum.reduce(files, %{}, fn file, acc ->
      full = Path.join(dir, file)

      case File.read(full) do
        {:ok, content} ->
          key = Path.join("partials", Path.basename(full))
          Logger.debug(%{event: "partial_loaded", key: key, size: byte_size(content)})
          Map.put(acc, key, content)

        {:error, reason} ->
          Logger.warning(%{event: "partial_read_failed", path: full, reason: reason})
          acc
      end
    end)
  end
end
