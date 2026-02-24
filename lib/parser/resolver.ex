defmodule Parser.Resolver do
  @moduledoc """
  Holds any operations necessary for the server to resolve template dependencies
  """

  @doc """
  Resolves an unsanitized partial reference to its contents

  ## Examples

  iex> Parser.Resolver.resolve_partial_reference(" head.html", %Parser.ParseInput{ partials: %{ "partials/head.html" => "hello world"}, base_url: "/priv/templates", file: "index.html"})
  "hello world"

  iex> Parser.Resolver.resolve_partial_reference(" head.html", %Parser.ParseInput{ partials: %{}, base_url: "", file: "index.html" })
  nil
  """
  def resolve_partial_reference(string, parse_input) do
    with {:ok, key} <-
           string
           |> String.trim()
           |> then(&resolve_path(["partials", &1], parse_input.base_url)) do
      Map.get(parse_input.partials, key)
    end
  end

  @doc """
  Resolves an unsanitized partial reference to its contents

  ## Examples

  iex> Parser.Resolver.resolve_page(" index.html", "/priv/templates")
  {:ok, "pages/index.html"}

  iex> Parser.Resolver.resolve_page("nonexistent.html", "/priv/templates")
  {:ok, "pages/nonexistent.html"} # We don't check for file existence
  """
  def resolve_page(string, base_url) do
    string
    |> String.trim()
    |> then(&resolve_path(["pages", &1], base_url))
  end

  @doc """
  Resolves a template's potentially relative path to the Application's base_dir

  ## Examples

  iex> Parser.Resolver.resolve_path(["./file.html"], "/priv/templates")
  {:ok, "file.html"}
  """
  def resolve_path(rel_paths, base_dir) do
    Path.safe_relative(Path.join(rel_paths), base_dir)
  end
end
