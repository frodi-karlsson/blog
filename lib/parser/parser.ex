defmodule Parser do
  @moduledoc """
  Deals with parsing the templating language and returning valid HTML
  """

  @doc """
  Interpolates any used templates.
  Returns {:ok, content} or {:error, reason}
  """
  def parse(parse_input) do
    regex = ~r|<%(.*?)%/>|
    matches = Regex.scan(regex, parse_input.file, return: :index)

    final =
      Enum.reduce_while(
        matches,
        %{
          out: "",
          cursor: 0
        },
        fn match, acc -> reduce_match(match, acc, parse_input) end
      )

    case final do
      {:error, _} = final -> final
      final -> {:ok, final.out <> String.slice(parse_input.file, final.cursor..-1//1)}
    end
  end

  defp reduce_match(curr, acc, parse_input) do
    case parse_match(curr, parse_input) do
      {:ok, [{index, len}, _, str]} ->
        {:cont,
         %{
           out: acc.out <> String.slice(parse_input.file, acc.cursor, index - acc.cursor) <> str,
           cursor: index + len
         }}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp parse_match([{index, len}, {capture_index, capture_len}], parse_input) do
    case Parser.Resolver.resolve_partial_reference(
           String.slice(parse_input.file, capture_index, capture_len),
           parse_input
         ) do
      str when is_binary(str) ->
        {:ok, [{index, len}, {capture_index, capture_len}, str]}

      nil ->
        {:error, {:ref_not_found, String.slice(parse_input.file, capture_index, capture_len)}}
    end
  end
end
