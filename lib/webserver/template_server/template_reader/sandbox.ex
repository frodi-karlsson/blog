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
       "partials/head.html" => ~S"""
       <head>
         <title>Hello world</title>
       </head>
       """,
       "partials/blog.html" => ~S"""
       <div class="blog">
         <h1 class="title">
         <p class="body">
       </div>
       """
     }}
  end

  def get_partials(_base_url), do: {:error, :not_found}

  @impl true
  def read_page(_base_url, path) do
    case path do
      "index.html" ->
        {:ok,
         ~S"""
         <html>
           <% head.html %/>
           <body>
           </body>
         </html>
         """}

      "blog/index.html" ->
        {:ok, "<html><body>Blog Index</body></html>"}

      "blog/building-an-elixir-webserver-from-scratch.html" ->
        {:ok, "<html><body>First Post</body></html>"}

      "blog.html" ->
        {:error, :eisdir}

      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  def read_partial(_base_url, "head.html"), do: {:ok, "<head>...</head>"}

  def read_partial(_base_url, filename) when is_binary(filename),
    do: {:ok, "<partial>#{filename}</partial>"}

  @impl true
  def read_manifest(_base_url) do
    {:ok,
     Jason.encode!([
       %{
         "id" => "building-an-elixir-webserver-from-scratch",
         "title" => "Sandbox Post",
         "date" => "Feb 24, 2024",
         "category" => "Test",
         "summary" => "Summary"
       }
     ])}
  end

  @impl true
  def read_pages_manifest(_base_url) do
    {:ok,
     Jason.encode!([
       %{
         "id" => "index",
         "title" => "Home",
         "path" => "/"
       }
     ])}
  end
end
