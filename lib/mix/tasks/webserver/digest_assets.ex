defmodule Mix.Tasks.Webserver.DigestAssets do
  @moduledoc "Digests static assets in priv/static/ for cache busting."
  @shortdoc "Digests static assets"

  use Mix.Task

  @static_dir "priv/static"
  @manifest_filename "assets.json"
  @asset_extensions [".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".webp"]
  @hashed_pattern ~r/\.[a-f0-9]{64}\./

  @impl true
  def run(_) do
    IO.puts("Digesting static assets in #{@static_dir}...")

    case find_digestible_assets() do
      {:ok, assets} ->
        manifest = digest_assets(assets)
        manifest_path = Path.join(@static_dir, @manifest_filename)
        File.write!(manifest_path, Jason.encode_to_iodata!(manifest, pretty: true))
        IO.puts("Manifest written to #{manifest_path} (#{map_size(manifest)} entries)")

      {:error, reason} ->
        Mix.raise("Failed to discover assets: #{inspect(reason)}")
    end
  end

  defp find_digestible_assets do
    case list_all_files(@static_dir) do
      {:ok, files} ->
        {:ok, files |> Enum.filter(&digestible?/1) |> Enum.sort()}

      {:error, reason} ->
        {:error, "Error listing #{@static_dir}: #{reason}"}
    end
  end

  defp digestible?(relative_path) do
    Path.extname(relative_path) in @asset_extensions and
      not String.ends_with?(relative_path, @manifest_filename) and
      not Regex.match?(@hashed_pattern, relative_path)
  end

  defp list_all_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.flat_map(&list_files_recursively(Path.join(dir, &1), dir))

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_files_recursively(path, base_dir) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, entries} ->
          Enum.flat_map(entries, &list_files_recursively(Path.join(path, &1), base_dir))

        {:error, _} ->
          []
      end
    else
      [Path.relative_to(path, base_dir)]
    end
  end

  defp digest_assets(assets) do
    Map.new(assets, fn relative_path ->
      source = Path.join(@static_dir, relative_path)
      content = File.read!(source)
      hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      ext = Path.extname(relative_path)
      hashed_name = Path.rootname(relative_path) <> ".#{hash}" <> ext
      hashed_path = Path.join(@static_dir, hashed_name)

      File.mkdir_p!(Path.dirname(hashed_path))
      File.cp!(source, hashed_path)

      {relative_path, hashed_name}
    end)
  end
end
