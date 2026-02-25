defmodule Webserver.AssetServer do
  @moduledoc """
  Manages static asset paths and manifest resolution using ETS.
  """

  use GenServer
  require Logger

  @table_name :asset_manifest
  @asset_extensions [".css", ".js", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".webp"]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec resolve(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def resolve(path) when is_binary(path) do
    case :ets.lookup(@table_name, path) do
      [{^path, resolved}] -> {:ok, resolved}
      [] -> {:error, :not_found}
    end
  end

  @spec reload() :: :ok
  def reload do
    GenServer.cast(__MODULE__, :reload)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:set, :public, :named_table])
    state = %{static_dir: Path.join(to_string(:code.priv_dir(:webserver)), "static")}
    {:ok, state, {:continue, :load_manifest}}
  end

  @impl true
  def handle_continue(:load_manifest, state) do
    manifest = load_manifest(state.static_dir)
    :ets.insert(@table_name, Map.to_list(manifest))
    {:noreply, state}
  end

  @impl true
  def handle_cast(:reload, state) do
    :ets.delete_all_objects(@table_name)
    manifest = load_manifest(state.static_dir)
    :ets.insert(@table_name, Map.to_list(manifest))
    {:noreply, state}
  end

  defp load_manifest(static_dir) do
    manifest_path = Path.join(static_dir, "assets.json")

    Logger.debug(event: "load_manifest", static_dir: static_dir, exists: File.exists?(static_dir))

    case File.read(manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} ->
            Logger.debug(event: "manifest_loaded", keys: Map.keys(manifest))
            add_leading_slash(manifest)

          {:error, _} ->
            Logger.debug(event: "manifest_parse_error")
            build_identity_manifest(static_dir)
        end

      {:error, reason} ->
        Logger.debug(event: "manifest_read_error", reason: reason)
        build_identity_manifest(static_dir)
    end
  end

  defp add_leading_slash(manifest) do
    Map.new(manifest, fn {k, v} -> {"/static/" <> k, "/static/" <> v} end)
  end

  defp build_identity_manifest(static_dir) do
    case File.ls(static_dir) do
      {:ok, entries} ->
        files = Enum.flat_map(entries, &scan_static_entry(&1, static_dir))
        add_leading_slash(Map.new(files, fn f -> {f, f} end))

      {:error, _} ->
        %{}
    end
  end

  defp scan_static_entry(entry, static_dir) do
    path = Path.join(static_dir, entry)

    if File.dir?(path) do
      list_all_files(path, static_dir)
    else
      if asset_extension?(path, @asset_extensions) do
        [Path.relative_to(path, static_dir)]
      else
        []
      end
    end
  end

  defp asset_extension?(path, extensions) do
    Enum.member?(extensions, Path.extname(path))
  end

  defp list_all_files(dir, base_dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, &list_file_entry(&1, dir, base_dir))

      {:error, _} ->
        []
    end
  end

  defp list_file_entry(entry, dir, base_dir) do
    path = Path.join(dir, entry)

    if File.dir?(path) do
      list_all_files(path, base_dir)
    else
      if asset_extension?(path, @asset_extensions) do
        [Path.relative_to(path, base_dir)]
      else
        []
      end
    end
  end
end
