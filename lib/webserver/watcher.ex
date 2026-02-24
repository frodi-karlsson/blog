defmodule Webserver.Watcher do
  @moduledoc """
  Filesystem watcher that reacts to template and static asset changes.
  """
  use GenServer
  require Logger

  alias Webserver.LiveReload.PubSub
  alias Webserver.TemplateServer.Cache

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    if Application.get_env(:webserver, :live_reload) do
      :fs.subscribe()
      base_url = Application.get_env(:webserver, :base_url)
      :fs.start_link(:template_watcher, Path.expand(base_url))
      :fs.start_link(:static_watcher, Path.expand("priv/static"))

      {:ok, %{base_url: Path.expand(base_url)}}
    else
      :ignore
    end
  end

  def handle_info({_pid, {:fs, :file_event}, {path, _events}}, state) do
    path_str = List.to_string(path)

    cond do
      String.contains?(path_str, state.base_url) ->
        handle_template_change(path_str, state.base_url)

      String.ends_with?(path_str, ".css") ->
        broadcast_reload(:css)

      String.contains?(path_str, "priv/static") ->
        broadcast_reload(:full)

      true ->
        :ok
    end

    {:noreply, state}
  end

  defp handle_template_change(path, base_url) do
    rel_path = Path.relative_to(path, base_url)

    case Path.split(rel_path) do
      ["pages", filename] ->
        GenServer.cast(Cache, {:invalidate, filename})
        broadcast_reload(:full)

      ["partials", _filename] ->
        Cache.force_refresh()
        broadcast_reload(:full)

      _ ->
        :ok
    end
  end

  defp broadcast_reload(type) do
    PubSub.broadcast({:reload, type})
  end
end
