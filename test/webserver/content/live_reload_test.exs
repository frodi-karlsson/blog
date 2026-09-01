defmodule Webserver.Content.LiveReloadTest do
  use ExUnit.Case, async: false

  alias Webserver.Content.Store
  alias Webserver.Content.TemplateReader.MutableSandbox

  defp seed_page(id, opts) do
    date = Keyword.fetch!(opts, :date)
    tags = Keyword.get(opts, :tags, "")

    """
    ---
    title: #{id}
    date: #{date}
    summary: summary of #{id}
    tags: #{tags}
    ---
    <% layout.html %>
      <slot:title>#{id}</slot:title>
      <slot:description>d</slot:description>
      <slot:canonical></slot:canonical>
      <slot:og_type>article</slot:og_type>
      <slot:body><h1>#{id}</h1></slot:body>
    <%/ layout.html %>
    """
  end

  setup do
    initial = %{
      "post-a.html" => seed_page("A", date: "2026-05-01", tags: "alpha"),
      "post-b.html" => seed_page("B", date: "2026-04-01", tags: "beta")
    }

    {:ok, _} = MutableSandbox.start_link(initial)

    on_exit(fn ->
      try do
        MutableSandbox.stop()
      catch
        :exit, _ -> :ok
      end
    end)

    name = :"live_reload_cache_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      GenServer.start_link(
        Store,
        {"/priv/templates", 0, MutableSandbox, false, name},
        name: name
      )

    {:ok, name: name}
  end

  test "adding a new post shows up on refresh", %{name: name} do
    assert Store.posts_by_tag(name, "gamma") == []

    MutableSandbox.put_page("post-c.html", seed_page("C", date: "2026-06-01", tags: "gamma"))
    GenServer.cast(name, :refresh_content)
    _ = GenServer.call(name, :get_partials)

    posts = Store.posts_by_tag(name, "gamma")
    assert Enum.map(posts, & &1.id) == ["post-c"]
    assert {:ok, _} = Store.get_page(name, "tags/gamma.html")
  end

  test "editing a post to change tags updates tag pages and DB", %{name: name} do
    assert Store.posts_by_tag(name, "alpha") |> Enum.map(& &1.id) == ["post-a"]

    MutableSandbox.put_page("post-a.html", seed_page("A", date: "2026-05-01", tags: "delta"))
    GenServer.cast(name, :refresh_content)
    _ = GenServer.call(name, :get_partials)

    assert Store.posts_by_tag(name, "alpha") == []
    assert Store.posts_by_tag(name, "delta") |> Enum.map(& &1.id) == ["post-a"]

    assert {:ok, _} = Store.get_page(name, "tags/delta.html")
    assert {:error, :not_found} = Store.get_page(name, "tags/alpha.html")
  end

  test "removing the last post with a tag drops the tag page", %{name: name} do
    assert {:ok, _} = Store.get_page(name, "tags/beta.html")

    MutableSandbox.delete_page("post-b.html")
    GenServer.cast(name, :refresh_content)
    _ = GenServer.call(name, :get_partials)

    assert Store.posts_by_tag(name, "beta") == []
    assert {:error, :not_found} = Store.get_page(name, "tags/beta.html")

    # Untouched tag still works
    assert {:ok, _} = Store.get_page(name, "tags/alpha.html")
  end
end
