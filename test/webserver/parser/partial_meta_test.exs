defmodule Webserver.Parser.PartialMetaTest do
  use ExUnit.Case, async: true

  alias Webserver.Parser.PartialMeta

  test "extracts slot names" do
    meta = PartialMeta.build("<div>{{title}}{{body}}</div>")

    assert meta.slots == MapSet.new(["title", "body"])
    assert meta.attrs == MapSet.new()
  end

  test "extracts attr names" do
    meta = PartialMeta.build(~S|<img src="{{@src}}" alt="{{@alt}}">|)

    assert meta.attrs == MapSet.new(["src", "alt"])
    assert meta.slots == MapSet.new()
  end

  test "deduplicates repeated names" do
    meta = PartialMeta.build("{{title}}{{title}}")

    assert meta.slots == MapSet.new(["title"])
  end

  test "does not treat an attr placeholder as a slot" do
    meta = PartialMeta.build("{{@src}}")

    assert meta.slots == MapSet.new()
    assert meta.attrs == MapSet.new(["src"])
  end

  test "ignores asset placeholders" do
    meta = PartialMeta.build("{{+ /static/app.css}}")

    assert meta.slots == MapSet.new()
    assert meta.attrs == MapSet.new()
  end

  test "build_all/1 maps every partial to its meta" do
    metas = PartialMeta.build_all(%{"a.html" => "{{x}}", "b.html" => "{{@y}}"})

    assert metas["a.html"].slots == MapSet.new(["x"])
    assert metas["b.html"].attrs == MapSet.new(["y"])
  end
end
