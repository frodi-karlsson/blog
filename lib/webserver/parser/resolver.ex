defmodule Webserver.Parser.Resolver do
  @moduledoc """
  Resolves template references to their filesystem paths, with directory
  traversal protection via `Path.safe_relative/2`.
  """

  alias Webserver.Parser.ParseInput

  @spec resolve_partial_reference(String.t(), ParseInput.t()) :: String.t() | nil
  def resolve_partial_reference(string, %ParseInput{} = parse_input) do
    case resolve_path(["partials", String.trim(string)], parse_input.base_url) do
      {:ok, key} -> Map.get(parse_input.partials, key)
      :error -> nil
    end
  end

  @spec resolve_page(String.t(), String.t()) :: {:ok, String.t()} | {:error, :invalid_path}
  def resolve_page(string, base_url) do
    case resolve_path(["pages", String.trim(string)], base_url) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_path}
    end
  end

  @spec resolve_path([String.t()], String.t()) :: {:ok, String.t()} | :error
  def resolve_path(rel_paths, base_dir) do
    Path.safe_relative(Path.join(rel_paths), base_dir)
  end
end
