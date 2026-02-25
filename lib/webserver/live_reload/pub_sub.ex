defmodule Webserver.LiveReload.PubSub do
  @moduledoc """
  A simple GenServer-based PubSub for handling LiveReload subscriptions.
  """
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(pid) do
    GenServer.call(__MODULE__, {:subscribe, pid})
  end

  def broadcast(message) do
    GenServer.cast(__MODULE__, {:broadcast, message})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, Map.put(state, pid, true)}
  end

  @impl true
  def handle_cast({:broadcast, message}, state) do
    Enum.each(state, fn {pid, _} ->
      send(pid, message)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, Map.delete(state, pid)}
  end
end
