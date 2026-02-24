defmodule TemplateServer do
  alias TemplateServer.TemplateReader
  use GenServer
  require Logger

  def start_link(base_url) do
    GenServer.start_link(__MODULE__, base_url)
  end

  @doc """
  Returns a map with the template files at the time of init

  iex> {:ok, pid} = GenServer.start_link(TemplateServer, "/priv/templates")
  iex> TemplateServer.get_partials(pid)["partials/head.html"]
  "<head>\n  <title>Hello world</title>\n</head>\n"
  """
  def get_partials(pid) do
    GenServer.call(pid, {:get})
  end

  @doc """
  Initializes the template watcher, reading the base_url once

  ## Examples

  iex> {:ok, result} = TemplateServer.init("/priv/templates")
  iex> result.base_url
  "/priv/templates"
  iex> result.files["partials/head.html"]
  "<head>\n  <title>Hello world</title>\n</head>\n"

  iex> TemplateServer.init(1)
  {:stop, {:invalid_base_url, 1}}
  """
  @impl true
  def init(base_url) when is_binary(base_url) do
    Logger.info(%{event: "template_server_initializing", base_url: base_url})

    case TemplateReader.get_partials(base_url) do
      {:ok, map} when is_map(map) ->
        Logger.info(%{
          event: "template_server_initialized",
          base_url: base_url,
          partial_count: map_size(map)
        })

        {:ok, %{base_url: base_url, files: map}}

      {:error, reason} ->
        Logger.error(%{event: "template_server_init_failed", base_url: base_url, reason: reason})
        {:stop, {reason, base_url}}
    end
  end

  @impl true
  def init(base_url) do
    Logger.error(%{event: "template_server_invalid_base_url", base_url: base_url})
    {:stop, {:invalid_base_url, base_url}}
  end

  @impl true
  def handle_call({:get}, _from, state) do
    Logger.debug(%{
      event: "partials_requested",
      base_url: state.base_url,
      partial_count: map_size(state.files)
    })

    {:reply, state.files, state}
  end
end
