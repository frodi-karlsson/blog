defmodule Webserver.Parser.Resolver do
  @moduledoc """
  Resolves template references to their filesystem paths, with directory
  traversal protection via `Path.safe_relative/2`.
  """

  alias Webserver.Parser.ParseInput

  @doc """
  Resolves an unsanitized partial reference to its contents.

  ## Examples

      iex> Webserver.Parser.Resolver.resolve_partial_reference(" head.html", %Webserver.Parser.ParseInput{partials: %{"partials/head.html" => "hello world"}, base_url: "/priv/templates", file: "index.html"})
      "hello world"

      iex> Webserver.Parser.Resolver.resolve_partial_reference(" head.html", %Webserver.Parser.ParseInput{partials: %{}, base_url: "", file: "index.html"})
      nil
  """
  @spec resolve_partial_reference(String.t(), ParseInput.t()) :: String.t() | nil
  def resolve_partial_reference(string, %ParseInput{} = parse_input) do
    with {:ok, key} <-
           string
           |> String.trim()
           |> then(&resolve_path(["partials", &1], parse_input.base_url)) do
      Map.get(parse_input.partials, key)
    end
  end

  @doc """
  Resolves an unsanitized page path to its relative filesystem path.

  ## Examples

      iex> Webserver.Parser.Resolver.resolve_page(" index.html", "/priv/templates")
      {:ok, "pages/index.html"}

      iex> Webserver.Parser.Resolver.resolve_page("nonexistent.html", "/priv/templates")
      {:ok, "pages/nonexistent.html"}
  """
  @spec resolve_page(String.t(), String.t()) :: {:ok, String.t()} | :error
  def resolve_page(string, base_url) do
    string
    |> String.trim()
    |> then(&resolve_path(["pages", &1], base_url))
  end

  @doc """
  Safely resolves a relative path, rejecting directory traversal attempts.

  ## Examples

      iex> Webserver.Parser.Resolver.resolve_path(["./file.html"], "/priv/templates")
      {:ok, "file.html"}
  """
  @spec resolve_path([String.t()], String.t()) :: {:ok, String.t()} | :error
  def resolve_path(rel_paths, base_dir) do
    Path.safe_relative(Path.join(rel_paths), base_dir)
  end
end
