defmodule Webserver.Content.ConfigTest do
  use ExUnit.Case, async: false

  alias Webserver.Content.Config

  defp unique_table, do: :"cfg_test_#{System.unique_integer([:positive])}"

  test "put/2 then get/1 round-trips the config" do
    table = unique_table()
    cfg = %{template_dir: "/tpl", check_interval: 500, reader: SomeReader, live_reload?: true}

    Config.put(table, cfg)

    assert Config.get(table) == cfg
  end

  test "check_interval/1 reads just the interval" do
    table = unique_table()

    Config.put(table, %{template_dir: "/tpl", check_interval: 250, reader: R, live_reload?: false})

    assert Config.check_interval(table) == 250
  end

  test "get/1 raises a clear error for an unknown table" do
    assert_raise ArgumentError, fn -> Config.get(unique_table()) end
  end

  test "configs for different tables do not collide" do
    a = unique_table()
    b = unique_table()

    Config.put(a, %{template_dir: "/a", check_interval: 1, reader: R, live_reload?: false})
    Config.put(b, %{template_dir: "/b", check_interval: 2, reader: R, live_reload?: false})

    assert Config.get(a).template_dir == "/a"
    assert Config.get(b).template_dir == "/b"
  end
end
