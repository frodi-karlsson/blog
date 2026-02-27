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

  test "should create page file with valid front-matter", %{slug: slug, path: path} do
    NewPost.run(["#{slug}"])
    assert File.exists?(path)

    {meta, body} = Webserver.FrontMatter.parse(File.read!(path))

    assert meta["title"] == slug
    assert meta["date"] == Date.utc_today() |> Date.to_iso8601()
    assert meta["canonical"] == "https://blog.frodikarlsson.com/#{slug}"

    assert body =~ "<% layout.html %>"
    assert body =~ "<slot:og_type>article</slot:og_type>"
    assert body =~ "<% blog_post.html %>"

    refute body =~ "<slot:canonical>"
    refute body =~ "<slot:description>"

    today_formatted = Webserver.FrontMatter.format_date(meta["date"])
    assert body =~ "<slot:date>#{today_formatted}</slot:date>"
  end

  test "should slugify title from spaces and special chars" do
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

  test "should raise if file already exists", %{slug: slug, path: path} do
    File.write!(path, "existing content")

    assert_raise Mix.Error, ~r/already exists/, fn ->
      NewPost.run(["#{slug}"])
    end
  end

  test "should raise when no title given" do
    assert_raise Mix.Error, ~r/Usage/, fn ->
      NewPost.run([])
    end
  end
end
