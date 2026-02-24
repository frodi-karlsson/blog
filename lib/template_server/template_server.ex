defmodule TemplateServer do
  alias TemplateServer.TemplateReader
  use GenServer

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
    case TemplateReader.get_partials(base_url) do
      {:ok, map} when is_map(map) -> {:ok, %{base_url: base_url, files: map}}
      {:error, _} = error -> {:stop, {error, base_url}}
    end
  end

  @impl true
  def init(base_url) do
    {:stop, {:invalid_base_url, base_url}}
  end

  @impl true
  def handle_call({:get}, _, state) do
    {:reply, state.files, state}
  end
end
