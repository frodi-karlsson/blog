defmodule Webserver.Assets do
  @moduledoc false

  @static_prefix "/static/"
  @manifest_filename "assets.json"
  @meta_filename "assets_meta.json"

  @responsive_widths [360, 480, 640, 728, 876, 1024]

  @asset_extensions [
    ".css",
    ".js",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".svg",
    ".ico",
    ".webp"
  ]

  @spec static_prefix() :: String.t()
  def static_prefix, do: @static_prefix

  @spec manifest_filename() :: String.t()
  def manifest_filename, do: @manifest_filename

  @spec meta_filename() :: String.t()
  def meta_filename, do: @meta_filename

  @spec asset_extensions() :: [String.t()]
  def asset_extensions, do: @asset_extensions

  @spec responsive_widths() :: [pos_integer()]
  def responsive_widths, do: @responsive_widths

  @spec raster_extensions() :: [String.t()]
  def raster_extensions, do: [".png", ".jpg", ".jpeg"]

  @spec image_extensions() :: [String.t()]
  def image_extensions, do: raster_extensions() ++ [".gif", ".webp"]

  @spec list_all_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list_all_files(dir, opts \\ []) when is_binary(dir) do
    relative? = Keyword.get(opts, :relative, false)

    case File.ls(dir) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.flat_map(&list_files_recursively(Path.join(dir, &1), dir, relative?))
          |> Enum.sort()

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_files_recursively(path, base_dir, relative?)
       when is_binary(path) and is_binary(base_dir) and is_boolean(relative?) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, entries} ->
          Enum.flat_map(
            entries,
            &list_files_recursively(Path.join(path, &1), base_dir, relative?)
          )

        {:error, _} ->
          []
      end
    else
      [if(relative?, do: Path.relative_to(path, base_dir), else: path)]
    end
  end
end
