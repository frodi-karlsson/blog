defmodule Mix.Tasks.Webserver.NewPost do
  @moduledoc """
  Scaffolds a new blog post with front-matter and the standard blog_post.html template.

  Usage:

      mix webserver.new_post "My Post Title"

  Creates `priv/templates/pages/{slug}.html` where the slug is derived from the
  title by lowercasing and replacing non-alphanumeric characters with hyphens.
  """
  @shortdoc "Scaffolds a new blog post"

  use Mix.Task

  @pages_dir "priv/templates/pages"

  @impl true
  def run([title | _]) do
    slug = slugify(title)
    path = Path.join(@pages_dir, "#{slug}.html")

    if File.exists?(path) do
      Mix.raise("#{path} already exists")
    end

    today = Date.utc_today() |> Date.to_iso8601()
    content = template(title, slug, today)

    File.mkdir_p!(@pages_dir)
    File.write!(path, content)
    Mix.shell().info("Created #{path}")
  end

  def run([]) do
    Mix.raise("Usage: mix webserver.new_post \"Post Title\"")
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp template(title, slug, date) do
    """
    ---
    title: #{title}
    date: #{date}
    category:
    summary:
    ---
    <% layout.html %>
      <slot:title>#{title}</slot:title>
      <slot:description></slot:description>
      <slot:canonical>https://blog.frodikarlsson.com/#{slug}</slot:canonical>
      <slot:og_type>article</slot:og_type>
      <slot:body>
        <% blog_post.html %>
          <slot:category></slot:category>
          <slot:date></slot:date>
          <slot:title>#{title}</slot:title>
          <slot:content>
            <p>Start writing here...</p>
          </slot:content>
        <%/ blog_post.html %>
      </slot:body>
    <%/ layout.html %>
    """
  end
end
