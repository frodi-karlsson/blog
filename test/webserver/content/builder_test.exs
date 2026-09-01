defmodule Webserver.Content.BuilderTest do
  use ExUnit.Case, async: true

  alias Webserver.Content.Builder
  alias Webserver.Content.TemplateReader.Sandbox

  defp state do
    %{
      template_dir: "/priv/templates",
      reader: Sandbox,
      live_reload?: false,
      partials: elem(Sandbox.get_partials("/priv/templates"), 1)
    }
  end

  test "build/1 returns rows with unique keys" do
    %{rows: rows} = Builder.build(state())
    keys = Enum.map(rows, &elem(&1, 0))

    assert keys == Enum.uniq(keys)
    assert length(rows) > 5
  end

  test "build/1 includes the posts db, page registry and path set" do
    %{rows: rows} = Builder.build(state())
    keys = Enum.map(rows, &elem(&1, 0))

    assert :posts_db in keys
    assert :page_registry in keys
    assert :page_path_set in keys
  end

  test "build/1 derives page_path_set from the registry" do
    %{rows: rows} = Builder.build(state())

    {_, registry} = List.keyfind(rows, :page_registry, 0)
    {_, path_set} = List.keyfind(rows, :page_path_set, 0)

    assert path_set == MapSet.new(Enum.map(registry, & &1["path"]))
  end

  test "build/1 returns generated tag page filenames so Store can prune" do
    %{tag_page_filenames: filenames} = Builder.build(state())

    assert %MapSet{} = filenames
    assert Enum.all?(filenames, &String.starts_with?(&1, "tags/"))
  end

  test "build/1 returns partials including the generated blog index" do
    %{partials: partials} = Builder.build(state())

    assert Map.has_key?(partials, "partials/generated_blog_items.html")
    assert Map.has_key?(partials, "partials/generated_livereload_script.html")
  end

  # The Sandbox's header_assets.html is a stub that, unlike the real
  # priv/templates one, does not reference the generated livereload partial. So
  # this test supplies a production-shaped header_assets: if `build/1` merged
  # the livereload partial into `partials` after rendering pages, the reference
  # below would not resolve, Generator would swallow the error, and every
  # generated page would silently be "".
  test "build/1 renders generated pages through the layout" do
    state =
      update_in(
        state().partials,
        &Map.put(&1, "partials/header_assets.html", ~S|<% generated_livereload_script.html %/>|)
      )

    %{rows: rows} = Builder.build(state)
    {_, entry} = List.keyfind(rows, {:page, "tags/index.html"}, 0)

    refute entry.parsed == ""
    assert entry.parsed =~ "<html"
  end

  test "build/1 emits an empty livereload script when live reload is off" do
    %{partials: partials} = Builder.build(state())

    assert partials["partials/generated_livereload_script.html"] == ""
  end

  test "build/1 emits a livereload script tag when live reload is on" do
    %{partials: partials} = Builder.build(%{state() | live_reload?: true})

    assert partials["partials/generated_livereload_script.html"] =~ "livereload.js"
  end
end
