defmodule Webserver.LiveReloadTest do
  use ExUnit.Case, async: false

  alias Webserver.LiveReload
  alias Webserver.LiveReload.PubSub

  @moduletag :capture_log

  defp call do
    LiveReload.call(Plug.Test.conn(:get, "/live-reload"), LiveReload.init([]))
  end

  describe "when PubSub is not running" do
    setup do
      # Production: the route is compiled in, but PubSub is only supervised
      # when live reload is on.
      case Process.whereis(PubSub) do
        nil -> :ok
        pid -> Agent.stop(pid)
      end

      :ok
    end

    test "responds 404 instead of crashing" do
      conn = call()

      assert conn.status == 404
      assert conn.state == :sent
    end

    test "does not commit a chunked response it cannot finish" do
      conn = call()

      refute conn.state == :chunked

      refute Enum.any?(conn.resp_headers, fn {k, v} ->
               k == "content-type" and v == "text/event-stream"
             end)
    end
  end
end
