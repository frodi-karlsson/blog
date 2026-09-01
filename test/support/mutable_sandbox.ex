defmodule Webserver.Content.TemplateReader.MutableSandbox do
  @moduledoc """
  Agent-backed template reader used by live-reload tests. Callers seed
  pages before starting the cache, then mutate the seeded state between
  refreshes to exercise add/edit/remove flows.
  """

  @behaviour Webserver.Content.TemplateReader

  use Agent

  @default_partials %{
    "partials/layout.html" => ~S"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="description" content="{{description}}">
      <link rel="canonical" href="{{canonical}}">
      <meta property="og:type" content="{{og_type}}">
      <title>{{title}}</title>
    </head>
    <body>{{body}}</body>
    </html>
    """,
    "partials/blog_index_item.html" => ~S"""
    <article>
      <p>{{tags}} - {{date}}</p>
      <h2><a href="{{url}}">{{title}}</a></h2>
      <p>{{summary}}</p>
    </article>
    """,
    "partials/tags_index.html" => ~S"""
    <div>{{chips}}</div>
    """,
    "partials/tag_page.html" => ~S"""
    <div><h1>{{tag}}</h1>{{items}}</div>
    """
  }

  def start_link(pages) do
    Agent.start_link(fn -> %{pages: pages, partials: @default_partials} end,
      name: __MODULE__
    )
  end

  def put_page(filename, contents) do
    Agent.update(__MODULE__, fn state ->
      %{state | pages: Map.put(state.pages, filename, contents)}
    end)
  end

  def delete_page(filename) do
    Agent.update(__MODULE__, fn state ->
      %{state | pages: Map.delete(state.pages, filename)}
    end)
  end

  def stop, do: Agent.stop(__MODULE__)

  @impl true
  def get_partials(_dir), do: {:ok, get_state().partials}

  @impl true
  def list_pages(_dir), do: {:ok, Map.keys(get_state().pages)}

  @impl true
  def read_page(_dir, filename) do
    case Map.fetch(get_state().pages, filename) do
      {:ok, content} -> {:ok, content}
      :error -> {:error, :not_found}
    end
  end

  @impl true
  def file_mtime(_dir, _relative_path), do: {{2026, 1, 1}, {0, 0, 0}}

  defp get_state, do: Agent.get(__MODULE__, & &1)
end
