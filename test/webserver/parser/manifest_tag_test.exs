defmodule Webserver.Parser.ManifestTagTest do
  # Not async — these tests insert into the shared ETS table managed by AssetServer
  use ExUnit.Case, async: false

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  setup do
    :ets.insert(:asset_manifest, {"/static/css/app.css", "/static/css/app.testhash.css"})

    on_exit(fn ->
      :ets.delete(:asset_manifest, "/static/css/app.css")
    end)

    :ok
  end

  test "resolves manifest tag to hashed path" do
    input = ~S(<link href="{% /static/css/app.css %}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:ok, ~S(<link href="/static/css/app.testhash.css">)}
  end

  test "returns error for unknown manifest key" do
    input = ~S(<link href="{% /static/css/missing.css %}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:error, {:unresolved_injection, "/static/css/missing.css"}}
  end

  test "handles manifest tag with no surrounding spaces" do
    input = ~S(<link href="{%/static/css/app.css%}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:ok, ~S(<link href="/static/css/app.testhash.css">)}
  end

  test "handles manifest tag with extra surrounding spaces" do
    input = ~S(<link href="{%  /static/css/app.css  %}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:ok, ~S(<link href="/static/css/app.testhash.css">)}
  end

  test "resolves multiple manifest tags in one template" do
    :ets.insert(:asset_manifest, {"/static/favicon.ico", "/static/favicon.testhash.ico"})

    on_exit(fn ->
      :ets.delete(:asset_manifest, "/static/favicon.ico")
    end)

    input =
      ~S(<link rel="icon" href="{% /static/favicon.ico %}"><link rel="stylesheet" href="{% /static/css/app.css %}">)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    expected =
      ~S(<link rel="icon" href="/static/favicon.testhash.ico"><link rel="stylesheet" href="/static/css/app.testhash.css">)

    assert result == {:ok, expected}
  end
end
