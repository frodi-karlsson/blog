defmodule Mix.Tasks.Assets.Build do
  @moduledoc """
  Builds static assets.

  1. Copies raw files from assets/static/ into priv/static/
  2. Generates responsive image variants for raster images (requires `vips`/`vipsheader`)
  3. Generates WebP variants (requires `cwebp`)
  4. Writes image dimension metadata to priv/static/assets_meta.json
  5. Digests all files in priv/static/ for cache busting
  """
  @shortdoc "Builds static assets"

  use Mix.Task

  @source_dir "assets/static"
  @output_dir "priv/static"

  alias Webserver.Assets

  @meta_filename Webserver.Assets.meta_filename()

  @image_extensions Webserver.Assets.raster_extensions()
  @dimension_extensions Webserver.Assets.image_extensions()
  @hashed_pattern ~r/\.[a-f0-9]{64}\./

  @responsive_widths Webserver.Assets.responsive_widths()

  @impl true
  def run(_args) do
    vips = ensure_executable!("vips")
    vipsheader = ensure_executable!("vipsheader")

    copy_static_files()

    generate_responsive_images(vips, vipsheader)

    optimize_images()

    generate_asset_metadata(vipsheader)

    Mix.Task.run("webserver.digest_assets", [])

    IO.puts("Assets built.")
  end

  defp copy_static_files do
    File.mkdir_p!(@output_dir)

    case File.ls(@source_dir) do
      {:ok, entries} ->
        for entry <- entries do
          source = Path.join(@source_dir, entry)
          dest = Path.join(@output_dir, entry)
          File.cp_r!(source, dest)
        end

      {:error, :enoent} ->
        :ok
    end
  end

  defp optimize_images do
    cwebp = ensure_executable!("cwebp")

    @output_dir
    |> list_all_files()
    |> Enum.filter(&image_source?/1)
    |> Enum.each(&maybe_generate_webp(&1, cwebp))
  end

  defp generate_responsive_images(vips, vipsheader)
       when is_binary(vips) and is_binary(vipsheader) do
    @output_dir
    |> list_all_files()
    |> Enum.filter(&raster_source_for_responsive?/1)
    |> Enum.each(&generate_responsive_variants(&1, vips, vipsheader))
  end

  defp raster_source_for_responsive?(path) do
    Path.extname(path) in [".png", ".jpg", ".jpeg"] and
      not Regex.match?(@hashed_pattern, path) and
      not responsive_variant?(path)
  end

  defp responsive_variant?(path) do
    String.match?(Path.basename(path), ~r/\.w\d+\.(png|jpe?g)$/)
  end

  defp generate_responsive_variants(source_path, vips, vipsheader)
       when is_binary(source_path) and is_binary(vips) and is_binary(vipsheader) do
    case image_dimensions(source_path, vipsheader) do
      {:ok, {src_w, _src_h}} when is_integer(src_w) and src_w > 0 ->
        base_no_ext = Path.rootname(source_path)
        ext = Path.extname(source_path)

        @responsive_widths
        |> Enum.filter(&(&1 < src_w))
        |> Enum.each(&maybe_generate_responsive_variant(source_path, vips, base_no_ext, ext, &1))

      _ ->
        :ok
    end
  end

  defp maybe_generate_responsive_variant(source_path, vips, base_no_ext, ext, w)
       when is_binary(source_path) and is_binary(vips) and is_binary(base_no_ext) and
              is_binary(ext) and
              is_integer(w) do
    output_path = base_no_ext <> ".w#{w}" <> ext

    if stale?(source_path, output_path) do
      run_vips_thumbnail(vips, source_path, output_path, w)
    else
      :ok
    end
  end

  defp run_vips_thumbnail(vips, source_path, output_path, w)
       when is_binary(vips) and is_binary(source_path) and is_binary(output_path) and
              is_integer(w) do
    args = [
      "--vips-concurrency=1",
      "--vips-cache-max=0",
      "--vips-cache-max-memory=0",
      "thumbnail",
      source_path,
      output_path,
      Integer.to_string(w)
    ]

    case System.cmd(vips, args, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        Mix.raise(
          "vips thumbnail failed (status=#{status}) for #{source_path} (w=#{w}):\n#{output}"
        )
    end
  end

  defp generate_asset_metadata(vipsheader) when is_binary(vipsheader) do
    {meta, failures} =
      @output_dir
      |> list_all_files()
      |> Enum.filter(&dimension_source?/1)
      |> Enum.reduce({%{}, []}, fn path, {acc, failures} ->
        case image_dimensions(path, vipsheader) do
          {:ok, {width, height}} ->
            rel = Path.relative_to(path, @output_dir)
            {Map.put(acc, rel, %{width: width, height: height}), failures}

          :error ->
            {acc, [path | failures]}
        end
      end)

    if failures != [] do
      failures = failures |> Enum.reverse() |> Enum.map_join("\n", &"- #{&1}")
      Mix.raise("Failed to extract image dimensions for:\n#{failures}")
    end

    meta_path = Path.join(@output_dir, @meta_filename)
    File.write!(meta_path, Jason.encode_to_iodata!(meta, pretty: true))
  end

  defp image_source?(path) do
    Path.extname(path) in @image_extensions and
      not Regex.match?(@hashed_pattern, path)
  end

  defp dimension_source?(path) do
    Path.extname(path) in @dimension_extensions and
      not Regex.match?(@hashed_pattern, path)
  end

  defp image_dimensions(path, vipsheader) when is_binary(path) and is_binary(vipsheader) do
    with {:ok, width} <- vipsheader_field(vipsheader, path, "width"),
         {:ok, height} <- vipsheader_field(vipsheader, path, "height") do
      {:ok, {width, height}}
    else
      :error ->
        :error
    end
  end

  defp vipsheader_field(vipsheader, path, field)
       when is_binary(vipsheader) and is_binary(path) and is_binary(field) do
    case System.cmd(vipsheader, ["-f", field, path], stderr_to_stdout: true) do
      {output, 0} ->
        output = String.trim(output)

        case Integer.parse(output) do
          {n, ""} when n > 0 -> {:ok, n}
          _ -> :error
        end

      {_output, _status} ->
        :error
    end
  end

  defp ensure_executable!(name) when is_binary(name) do
    case System.find_executable(name) do
      nil ->
        Mix.raise("Missing required executable: #{name}")

      exe ->
        exe
    end
  end

  defp maybe_generate_webp(source_path, cwebp) do
    output_path = Path.rootname(source_path) <> ".webp"

    if stale?(source_path, output_path) do
      args = cwebp_args_for(source_path, output_path)

      case System.cmd(cwebp, args, stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {output, status} ->
          Mix.raise("cwebp failed (status=#{status}) for #{source_path}:\n#{output}")
      end
    else
      :ok
    end
  end

  defp cwebp_args_for(source_path, output_path) do
    base = ["-quiet", "-mt"]

    opts =
      case Path.extname(source_path) do
        ".png" -> ["-lossless"]
        _ -> ["-q", "85"]
      end

    base ++ opts ++ [source_path, "-o", output_path]
  end

  defp stale?(source_path, output_path) do
    case File.stat(output_path) do
      {:ok, out_stat} ->
        case File.stat(source_path) do
          {:ok, src_stat} ->
            out_stat.mtime < src_stat.mtime

          {:error, _} ->
            false
        end

      {:error, _} ->
        File.exists?(source_path)
    end
  end

  defp list_all_files(dir) do
    case Assets.list_all_files(dir, relative: false) do
      {:ok, files} -> files
      {:error, _} -> []
    end
  end
end
