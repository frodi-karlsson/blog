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
  @callback get_partials(base_url :: String.t()) :: {:ok, partials()} | {:error, term()}

  @doc "Reads the raw content of a single page file."
  @callback read_page(base_url :: String.t(), path :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Reads the raw content of a single partial file by filename."
  @callback read_partial(base_url :: String.t(), filename :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
