defmodule Mix.Tasks.Webserver.NewPostTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Webserver.NewPost

  @pages_dir "priv/templates/pages"

  setup do
    slug = "test-post-#{System.unique_integer([:positive])}"
    path = Path.join(@pages_dir, "#{slug}.html")
    on_exit(fn -> File.rm(path) end)
    {:ok, slug: slug, path: path}
  end

  test "creates page file with front-matter and template", %{slug: slug, path: path} do
    NewPost.run(["#{slug}"])
    assert File.exists?(path)
    content = File.read!(path)
    assert String.starts_with?(content, "---\n")
    assert String.contains?(content, "title: #{slug}")
    assert String.contains?(content, "date: #{Date.utc_today() |> Date.to_iso8601()}")
    assert String.contains?(content, "<% blog_post.html %>")
    assert String.contains?(content, "<%/ blog_post.html %>")
    assert String.contains?(content, "<% layout.html %>")
  end

  test "slugifies title from spaces and special chars" do
    title = "My First Blog Post!"
    slug = "my-first-blog-post"
    path = Path.join(@pages_dir, "#{slug}.html")
    on_exit(fn -> File.rm(path) end)

    NewPost.run([title])
    assert File.exists?(path)
    content = File.read!(path)
    assert String.contains?(content, "title: My First Blog Post!")
    assert String.contains?(content, "/#{slug}")
  end

  test "raises if file already exists", %{slug: slug, path: path} do
    File.write!(path, "existing content")

    assert_raise Mix.Error, ~r/already exists/, fn ->
      NewPost.run(["#{slug}"])
    end
  end

  test "raises when no title given" do
    assert_raise Mix.Error, ~r/Usage/, fn ->
      NewPost.run([])
    end
  end
end
