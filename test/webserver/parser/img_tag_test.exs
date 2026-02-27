defmodule Webserver.Parser.ImgTagTest do
  # Not async — these tests insert into the shared ETS table managed by AssetServer
  use ExUnit.Case, async: false

  alias Webserver.Parser
  alias Webserver.Parser.ParseInput

  setup do
    ensure_table(:asset_manifest)
    ensure_table(:asset_meta)

    :ets.insert(
      :asset_manifest,
      {"/static/img/web-vitals.png", "/static/img/web-vitals.testhash.png"}
    )

    :ets.insert(
      :asset_manifest,
      {"/static/img/web-vitals.w728.png", "/static/img/web-vitals.w728.testhash.png"}
    )

    :ets.insert(:asset_meta, {"/static/img/web-vitals.png", %{width: 876, height: 378}})

    :ets.insert(
      :asset_manifest,
      {"/static/img/web-vitals.webp", "/static/img/web-vitals.testhash.webp"}
    )

    :ets.insert(
      :asset_manifest,
      {"/static/img/web-vitals.w728.webp", "/static/img/web-vitals.w728.testhash.webp"}
    )

    :ets.insert(:asset_meta, {"/static/img/web-vitals.webp", %{width: 876, height: 378}})

    on_exit(fn ->
      :ets.delete(:asset_manifest, "/static/img/web-vitals.png")
      :ets.delete(:asset_meta, "/static/img/web-vitals.png")
      :ets.delete(:asset_manifest, "/static/img/web-vitals.webp")
      :ets.delete(:asset_meta, "/static/img/web-vitals.webp")

      :ets.delete(:asset_manifest, "/static/img/web-vitals.w728.png")
      :ets.delete(:asset_manifest, "/static/img/web-vitals.w728.webp")
    end)

    :ok
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:named_table, :set, :public])
      _ -> :ok
    end
  end

  test "should render <picture> with webp variant and width/height" do
    input =
      ~S(<% img src='/static/img/web-vitals.png' alt='Vitals' %/>)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result ==
             {:ok,
              ~S(<picture><source type="image/webp" srcset="/static/img/web-vitals.w728.testhash.webp 728w, /static/img/web-vitals.testhash.webp 876w"><img src="/static/img/web-vitals.testhash.png" alt="Vitals" width="876" height="378" srcset="/static/img/web-vitals.w728.testhash.png 728w, /static/img/web-vitals.testhash.png 876w" decoding="async" /></picture>)}
  end

  test "should escape alt text" do
    input = ~S(<% img src='/static/img/web-vitals.png' alt='a"b<c&d' %/>)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result ==
             {:ok,
              ~S(<picture><source type="image/webp" srcset="/static/img/web-vitals.w728.testhash.webp 728w, /static/img/web-vitals.testhash.webp 876w"><img src="/static/img/web-vitals.testhash.png" alt="a&quot;b&lt;c&amp;d" width="876" height="378" srcset="/static/img/web-vitals.w728.testhash.png 728w, /static/img/web-vitals.testhash.png 876w" decoding="async" /></picture>)}
  end

  test "should error for non-image src" do
    input = ~S(<% img src='/static/css/app.css' alt='nope' %/>)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:error, {:non_image_src, "/static/css/app.css"}}
  end

  test "should error for missing image metadata" do
    :ets.delete(:asset_meta, "/static/img/web-vitals.png")

    input = ~S(<% img src='/static/img/web-vitals.png' alt='Vitals' %/>)

    result =
      Parser.parse(%ParseInput{file: input, partials: %{}, template_dir: "/priv/templates"})

    assert result == {:error, {:unresolved_image_meta, "/static/img/web-vitals.png"}}
  end
end
