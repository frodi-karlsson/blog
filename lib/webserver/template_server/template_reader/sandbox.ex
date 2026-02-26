defmodule Webserver.TemplateServer.TemplateReader.Sandbox do
  @moduledoc """
  In-memory template reader for testing. Returns predefined templates
  for the `/priv/templates` base URL and errors for any other path.
  """

  @behaviour Webserver.TemplateServer.TemplateReader

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
       "partials/blog.html" => ~S"""
       <div class="blog">
         <h1 class="title">
         <p class="body">
       </div>
       """
     }}
  end

  def get_partials(_template_dir), do: {:error, :not_found}

  @impl true
  def list_pages("/priv/templates") do
    {:ok, ["index.html", "bespoke-elixir-web-framework.html"]}
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
         category: Test
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

      "blog.html" ->
        {:error, :eisdir}

      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  def file_mtime(_template_dir, _relative_path), do: {{2024, 1, 1}, {0, 0, 0}}
end
