defmodule Mix.Tasks.Webserver.DigestAssets do
  @moduledoc "Digests static assets in priv/static/ for cache busting."
  @shortdoc "Digests static assets"

  use Mix.Task

  alias Webserver.Assets

  @static_dir "priv/static"
  @manifest_filename Webserver.Assets.manifest_filename()
  @meta_filename Webserver.Assets.meta_filename()
  @asset_extensions Webserver.Assets.asset_extensions()
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
    case Assets.list_all_files(@static_dir, relative: true) do
      {:ok, files} ->
        {:ok, files |> Enum.filter(&digestible?/1) |> Enum.sort()}

      {:error, reason} ->
        {:error, "Error listing #{@static_dir}: #{reason}"}
    end
  end

  defp digestible?(relative_path) do
    Path.extname(relative_path) in @asset_extensions and
      not String.ends_with?(relative_path, @manifest_filename) and
      not String.ends_with?(relative_path, @meta_filename) and
      not Regex.match?(@hashed_pattern, relative_path)
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
