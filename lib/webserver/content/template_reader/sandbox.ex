defmodule Webserver.Content.TemplateReader.Sandbox do
  @moduledoc """
  In-memory template reader for testing. Returns predefined templates
  for the `/priv/templates` base URL and errors for any other path.
  """

  @behaviour Webserver.Content.TemplateReader

  @impl true
  def get_partials("/priv/templates") do
    {:ok,
     %{
       "partials/layout.html" => ~S"""
       <!DOCTYPE html>
       <html lang="en">
       <head>
         <meta name="description" content="{{description}}">
         <link rel="canonical" href="{{canonical}}">
         <meta property="og:type" content="{{og_type}}">
         <meta property="og:title" content="{{title}}">
         <title>{{title}}</title>
         <% header_assets.html %/>
       </head>
       <body>
         {{body}}
         <% footer_assets.html %/>
       </body>
       </html>
       """,
       "partials/header_assets.html" => "<header-assets/>",
       "partials/footer_assets.html" => "<footer-assets/>",
       "partials/blog_index_item.html" => ~S"""
       <article data-testid="blog-index-item">
         <p class="text-subtle">{{tags}} · {{date}}</p>
         <h2><a href="{{url}}">{{title}}</a></h2>
         <p>{{summary}}</p>
       </article>
       """,
       "partials/tags_index.html" => ~S"""
       <div class="stack stack--loose">
         <header data-testid="tags-index-header">
           <h1>Tags</h1>
           <p class="text-subtle"><a href="/">← All posts</a></p>
         </header>

         <div class="cluster" data-testid="tag-chip-list">
           {{chips}}
         </div>
       </div>
       """,
       "partials/tag_page.html" => ~S"""
       <div class="stack stack--loose">
         <header data-testid="tag-page-header">
           <p class="text-subtle"><a href="/tags">← All tags</a></p>
           <h1>Posts tagged <code>{{tag}}</code></h1>
         </header>

         <div class="grid">
           {{items}}
         </div>
       </div>
       """
     }}
  end

  def get_partials(_template_dir), do: {:error, :not_found}

  @impl true
  def list_pages("/priv/templates") do
    {:ok, ["index.html", "bespoke-elixir-web-framework.html", "post-a.html", "post-b.html"]}
  end

  def list_pages(_template_dir), do: {:error, :not_found}

  @impl true
  def read_page(_template_dir, path) do
    case path do
      "index.html" ->
        {:ok,
         """
         ---
         title: Home
         ---
         <% layout.html %>
           <slot:title>Home</slot:title>
           <slot:description>Sandbox Home</slot:description>
           <slot:canonical>http://localhost/</slot:canonical>
           <slot:og_type>website</slot:og_type>
           <slot:body>
             <h1>Home</h1>
           </slot:body>
         <%/ layout.html %>
         """}

      "bespoke-elixir-web-framework.html" ->
        {:ok,
         """
         ---
         title: First Post
         date: 2024-02-24
         tags: test
         summary: Summary
         ---
         <% layout.html %>
           <slot:title>First Post</slot:title>
           <slot:description>Sandbox Post</slot:description>
           <slot:canonical>http://localhost/first-post</slot:canonical>
           <slot:og_type>article</slot:og_type>
           <slot:body>
             <h1>First Post</h1>
           </slot:body>
         <%/ layout.html %>
         """}

      "post-a.html" ->
        {:ok,
         """
         ---
         title: Post A
         date: 2026-05-01
         summary: About A
         tags: anabranch, TypeScript
         ---
         <% layout.html %>
           <slot:title>Post A</slot:title>
           <slot:description>Sandbox Post A</slot:description>
           <slot:canonical>http://localhost/post-a</slot:canonical>
           <slot:og_type>article</slot:og_type>
           <slot:body><h1>A</h1></slot:body>
         <%/ layout.html %>
         """}

      "post-b.html" ->
        {:ok,
         """
         ---
         title: Post B
         date: 2026-04-01
         summary: About B
         tags: elixir
         ---
         <% layout.html %>
           <slot:title>Post B</slot:title>
           <slot:description>Sandbox Post B</slot:description>
           <slot:canonical>http://localhost/post-b</slot:canonical>
           <slot:og_type>article</slot:og_type>
           <slot:body><h1>B</h1></slot:body>
         <%/ layout.html %>
         """}

      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  def file_mtime(_template_dir, _relative_path), do: {{2024, 1, 1}, {0, 0, 0}}
end
