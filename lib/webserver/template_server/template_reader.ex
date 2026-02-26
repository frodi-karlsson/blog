defmodule Webserver.TemplateServer.TemplateReader do
  @moduledoc """
  Behaviour for reading HTML templates from a source.

  Two implementations are provided:
  - `Webserver.TemplateServer.TemplateReader.File` — reads from the filesystem (dev/prod)
  - `Webserver.TemplateServer.TemplateReader.Sandbox` — returns in-memory fixtures (test)

  The active implementation is configured via:

      config :webserver, :template_reader, Webserver.TemplateServer.TemplateReader.File
  """

  @type partials :: %{String.t() => String.t()}

  @doc "Returns all partials as a map of `\"partials/filename.html\" => content`."
  @callback get_partials(template_dir :: String.t()) :: {:ok, partials()} | {:error, term()}

  @doc "Reads the raw content of a single page file."
  @callback read_page(template_dir :: String.t(), path :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Returns the relative filenames of all page files, e.g. index.html or admin/design-system.html."
  @callback list_pages(template_dir :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @doc "Returns the mtime for a file relative to template_dir, or nil if unavailable."
  @callback file_mtime(template_dir :: String.t(), relative_path :: String.t()) ::
              :calendar.datetime() | nil
end
