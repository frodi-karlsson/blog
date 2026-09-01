defmodule Webserver.Parser.Resolver do
  @moduledoc """
  Resolves template references to their filesystem paths, with directory
  traversal protection via `Path.safe_relative/2`.
  """

  alias Webserver.Parser.ParseInput

  @doc """
  The `partials`/`compiled_partials` map key for a partial reference.

  Single-sourced so the raw-text and compiled-template lookups cannot drift:
  a mismatch would silently miss and fall back to compiling on demand.
  """
  @spec partial_key(String.t()) :: String.t()
  def partial_key(string), do: Path.join("partials", String.trim(string))

  @spec resolve_partial_reference(String.t(), ParseInput.t()) :: String.t() | nil
  def resolve_partial_reference(string, %ParseInput{} = parse_input) do
    Map.get(parse_input.partials, partial_key(string))
  end

  @spec resolve_page(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def resolve_page(string, template_dir) do
    case resolve_path(["pages", String.trim(string)], template_dir) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :not_found}
    end
  end

  @spec resolve_path([String.t()], String.t()) :: {:ok, String.t()} | :error
  def resolve_path(rel_paths, base_dir) do
    Path.safe_relative(Path.join(rel_paths), base_dir)
  end
end
