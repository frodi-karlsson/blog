defmodule Webserver.LiveReload.PubSubTest do
  use ExUnit.Case, async: true

  alias Webserver.LiveReload.PubSub

  setup do
    case GenServer.whereis(PubSub) do
      nil -> start_supervised(PubSub)
      _pid -> :ok
    end

    :ok
  end

  test "should subscribe and broadcast messages" do
    PubSub.subscribe(self())
    PubSub.broadcast({:reload, :css})
    assert_receive {:reload, :css}
  end
end
