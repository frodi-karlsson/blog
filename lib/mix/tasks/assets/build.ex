defmodule Mix.Tasks.Assets.Build do
  @moduledoc """
  Builds static assets.

  1. Copies raw files from assets/static/ into priv/static/
  2. In prod, digests all files in priv/static/ for cache busting
  """
  @shortdoc "Builds static assets"

  use Mix.Task

  @source_dir "assets/static"
  @output_dir "priv/static"

  @impl true
  def run(_args) do
    copy_static_files()

    if Mix.env() == :prod do
      Mix.Task.run("webserver.digest_assets", [])
    end

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
end
