defmodule Webserver.TemplateServer.Post do
  @moduledoc """
  A blog post record built from a page's frontmatter. Stored in the cache
  under `{:posts_db, [%Post{}]}` and consumed by tag pages and search.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          filename: String.t(),
          path: String.t(),
          title: String.t(),
          date: Date.t(),
          summary: String.t(),
          tags: [String.t()],
          canonical: String.t() | nil,
          noindex: boolean()
        }

  defstruct [
    :id,
    :filename,
    :path,
    :title,
    :date,
    :summary,
    :tags,
    :canonical,
    :noindex
  ]

  @doc """
  Reshapes a `%Post{}` into the string-keyed meta map that
  `BlogItemRenderer.render/4` accepts. Used at request time (search results)
  and at cache-init time (per-tag pages).
  """
  @spec to_meta(t()) :: %{String.t() => term()}
  def to_meta(%__MODULE__{} = post) do
    %{
      "title" => post.title,
      "date" => Date.to_iso8601(post.date),
      "summary" => post.summary,
      "path" => post.path,
      "tags" => post.tags
    }
  end
end
