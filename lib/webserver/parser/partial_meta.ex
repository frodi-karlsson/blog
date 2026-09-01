defmodule Webserver.Parser.PartialMeta do
  @moduledoc """
  The set of slot and attribute names a partial declares.

  These are pure functions of the partial's text, which is fixed when partials
  are loaded, but the parser previously re-derived them with a regex scan on
  every render of every partial. Computing them once at load time removes that
  work from the request path.
  """

  @slot_placeholder_regex ~r|\{\{([a-z_]+)\}\}|
  @attr_placeholder_regex ~r|\{\{@([a-zA-Z0-9_\-]+)\}\}|

  defstruct slots: MapSet.new(), attrs: MapSet.new()

  @type t :: %__MODULE__{slots: MapSet.t(String.t()), attrs: MapSet.t(String.t())}

  @spec build(String.t()) :: t()
  def build(partial) when is_binary(partial) do
    %__MODULE__{
      slots: names(@slot_placeholder_regex, partial),
      attrs: names(@attr_placeholder_regex, partial)
    }
  end

  @spec build_all(%{String.t() => String.t()}) :: %{String.t() => t()}
  def build_all(partials), do: Map.new(partials, fn {key, text} -> {key, build(text)} end)

  defp names(regex, partial) do
    regex
    |> Regex.scan(partial)
    |> MapSet.new(fn [_full, name] -> name end)
  end
end
