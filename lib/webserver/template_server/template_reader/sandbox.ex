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

  def get_partials(_base_url), do: {:error, :enoent}

  @impl true
  def read_page(_base_url, path) do
    if String.ends_with?(path, "index.html") do
      {:ok,
       ~S"""
       <html>
         <% head.html %/>
         <body>
         </body>
       </html>
       """}
    else
      {:error, :enoent}
    end
  end

  @impl true
  def read_partial(_base_url, "head.html"), do: {:ok, "<head>...</head>"}

  def read_partial(_base_url, filename) when is_binary(filename),
    do: {:ok, "<partial>#{filename}</partial>"}
end
