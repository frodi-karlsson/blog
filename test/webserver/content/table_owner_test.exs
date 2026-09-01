defmodule Webserver.Content.TableOwnerTest do
  use ExUnit.Case, async: false

  alias Webserver.Content.Store
  alias Webserver.Content.TableOwner
  alias Webserver.Content.TemplateReader.Sandbox

  test "creates a public named table" do
    table = :"owner_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = TableOwner.start_link(table)

    assert :ets.whereis(table) != :undefined
    assert :ets.info(table, :protection) == :public
  end

  test "start_link is idempotent when the table already exists" do
    table = :"owner_test_#{System.unique_integer([:positive])}"
    {:ok, _} = TableOwner.start_link(table)

    assert {:error, {:already_started, _pid}} = TableOwner.start_link(table)
  end

  test "the cache survives a Store crash when TableOwner owns the table" do
    table = :"owner_test_#{System.unique_integer([:positive])}"
    {:ok, _owner} = TableOwner.start_link(table)

    {:ok, store} =
      GenServer.start(Store, {"/priv/templates", 0, Sandbox, false, table}, name: table)

    assert {:ok, html} = Store.get_page(table, "index.html")
    assert html != ""

    ref = Process.monitor(store)
    Process.exit(store, :kill)
    assert_receive {:DOWN, ^ref, :process, ^store, :killed}, 1000

    # The table and its rows outlive the Store process.
    assert :ets.whereis(table) != :undefined
    assert [{_, _}] = :ets.lookup(table, {:page, "index.html"})
  end

  test "a stale revalidate_in_flight marker does not survive a Store restart" do
    table = :"owner_test_#{System.unique_integer([:positive])}"
    {:ok, _owner} = TableOwner.start_link(table)

    {:ok, store} =
      GenServer.start(Store, {"/priv/templates", 0, Sandbox, false, table}, name: table)

    # Simulate a crash that left a marker behind.
    :ets.insert(table, {{:revalidate_in_flight, "index.html"}, true})

    ref = Process.monitor(store)
    Process.exit(store, :kill)
    assert_receive {:DOWN, ^ref, :process, ^store, :killed}, 1000

    {:ok, _restarted} =
      GenServer.start(Store, {"/priv/templates", 0, Sandbox, false, table}, name: table)

    assert :ets.lookup(table, {:revalidate_in_flight, "index.html"}) == [],
           "a stale in-flight marker must not survive init, or revalidation for that page is disabled forever"
  end
end
