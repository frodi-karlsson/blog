defmodule Webserver.Parser.AssetPlaceholderTest do
  # Not async — these tests insert into the shared ETS table managed by AssetServer
  use ExUnit.Case, async: false

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  setup do
    ensure_table(:asset_manifest)

    :ets.insert(:asset_manifest, {"/static/css/app.css", "/static/css/app.testhash.css"})

    on_exit(fn ->
      :ets.delete(:asset_manifest, "/static/css/app.css")
    end)

    :ok
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :set, :public])
      _ -> :ok
    end
  end

  test "should resolve {{+ /static/...}} placeholder to hashed path" do
    input = ~S(<link href="{{+ /static/css/app.css}}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:ok, ~S(<link href="/static/css/app.testhash.css">)}
  end

  test "should handle quoted asset placeholder" do
    input = ~S(<link href="{{+ '/static/css/app.css'}}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:ok, ~S(<link href="/static/css/app.testhash.css">)}
  end

  test "should return error for unknown asset placeholder" do
    input = ~S(<link href="{{+ /static/css/missing.css}}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:error, {:unresolved_asset, "/static/css/missing.css"}}
  end
end
