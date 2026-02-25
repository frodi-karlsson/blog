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

  def init({base_url, live_reload?}) do
    if live_reload? do
      :fs.subscribe()
      expanded = Path.expand(base_url)
      :fs.start_link(:template_watcher, expanded)
      :fs.start_link(:static_watcher, Path.expand("priv/static"))

      {:ok, %{base_url: expanded}}
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

    cond do
      String.ends_with?(path, "blog.json") ->
        GenServer.cast(Cache, :refresh_blog_index)
        broadcast_reload(:full)

      String.ends_with?(path, "pages.json") ->
        GenServer.cast(Cache, :refresh_page_registry)
        broadcast_reload(:full)

      true ->
        case Path.split(rel_path) do
          ["pages" | rest] ->
            filename = Path.join(rest)
            GenServer.cast(Cache, {:invalidate, filename})
            GenServer.cast(Cache, :refresh_blog_index)
            GenServer.cast(Cache, :refresh_page_registry)
            broadcast_reload(:full)

          ["partials" | _] ->
            Cache.force_refresh()
            broadcast_reload(:full)

          _ ->
            :ok
        end
    end
  end

  defp broadcast_reload(type) do
    PubSub.broadcast({:reload, type})
  end
end
