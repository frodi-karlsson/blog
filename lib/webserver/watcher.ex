defmodule Webserver.Watcher do
  @moduledoc """
  Filesystem watcher that reacts to template and static asset changes.
  """
  use GenServer
  require Logger

  alias Mix.Tasks.Webserver.DigestAssets
  alias Webserver.AssetServer
  alias Webserver.Content.Store
  alias Webserver.LiveReload.PubSub

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init({template_dir, live_reload?}) do
    if live_reload? do
      :fs.subscribe()
      expanded = Path.expand(template_dir)
      assets_static = Path.expand("assets/static")
      :fs.start_link(:template_watcher, expanded)
      :fs.start_link(:static_watcher, Path.expand("priv/static"))
      :fs.start_link(:assets_watcher, assets_static)

      {:ok, %{template_dir: expanded, assets_static_dir: assets_static}}
    else
      :ignore
    end
  end

  def handle_info({_pid, {:fs, :file_event}, {path, _events}}, state) do
    path_str = List.to_string(path)

    cond do
      String.contains?(path_str, state.template_dir) ->
        handle_template_change(path_str, state.template_dir)

      String.contains?(path_str, state.assets_static_dir) ->
        handle_assets_static_change(path_str, state.assets_static_dir)

      String.contains?(path_str, "priv/static") and digest_output?(path_str) ->
        :ok

      String.ends_with?(path_str, ".css") ->
        rebuild_digest()
        broadcast_reload(:css)

      String.contains?(path_str, "priv/static") ->
        rebuild_digest()
        broadcast_reload(:full)

      true ->
        :ok
    end

    {:noreply, state}
  end

  defp digest_output?(path_str) do
    Regex.match?(~r/\.[a-f0-9]{64}\./, path_str) or
      String.ends_with?(path_str, "assets.json") or
      String.ends_with?(path_str, "assets_meta.json")
  end

  defp rebuild_digest do
    DigestAssets.run([])
    AssetServer.reload_manifest()
  rescue
    e ->
      Logger.warning(%{event: "digest_rebuild_failed", error: Exception.message(e)})
  end

  defp handle_assets_static_change(path_str, assets_static_dir) do
    if File.regular?(path_str) do
      relative = Path.relative_to(path_str, assets_static_dir)
      dest = Path.join(Path.expand("priv/static"), relative)
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(path_str, dest)
    end

    broadcast_reload(:full)
  end

  defp handle_template_change(path, template_dir) do
    rel_path = Path.relative_to(path, template_dir)

    case Path.split(rel_path) do
      ["pages" | rest] ->
        filename = Path.join(rest)
        GenServer.cast(Store, {:invalidate, filename})
        GenServer.cast(Store, :refresh_content)
        broadcast_reload(:full)

      ["partials" | _] ->
        Store.force_refresh()
        broadcast_reload(:full)

      _ ->
        :ok
    end
  end

  defp broadcast_reload(type) do
    PubSub.broadcast({:reload, type})
  end
end
