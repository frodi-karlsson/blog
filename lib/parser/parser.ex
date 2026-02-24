defmodule Parser do
  @moduledoc """
  Deals with parsing the templating language and returning valid HTML
  """

  @doc """
  Interpolates any used templates.
  Supports two syntaxes:
  - Self-closing: <% partial.html %>
  - With slots: <% partial.html %>content<%/ partial.html %>
  Returns {:ok, content} or {:error, reason}
  """
  def parse(parse_input) do
    self_closing_regex = ~r|<%(.*?)%/>|

    file = parse_input.file

    file = process_slots(file, parse_input)

    final =
      Enum.reduce_while(
        Regex.scan(self_closing_regex, file, return: :index),
        %{
          out: "",
          cursor: 0
        },
        fn match, acc ->
          reduce_match(match, acc, %{parse_input | file: file})
        end
      )

    case final do
      {:error, _} = error -> error
      final -> {:ok, final.out <> String.slice(file, final.cursor..-1//1)}
    end
  end

  defp process_slots(file, parse_input) do
    slot_regex = ~r|<%\s*(.*?)\s*%>(.*?)<%/\s*\1\s*%>|s

    case Regex.run(slot_regex, file, return: :index) do
      nil ->
        file

      _match ->
        processed =
          Regex.replace(slot_regex, file, fn _full, name, content ->
            render_partial(name, content, parse_input)
          end)

        if processed == file do
          file
        else
          process_slots(processed, parse_input)
        end
    end
  end

  defp render_partial(name, content, parse_input) do
    partial_name = String.trim(name)

    case Parser.Resolver.resolve_partial_reference(partial_name, parse_input) do
      partial when is_binary(partial) ->
        rendered = String.replace(partial, "{{slot}}", content)
        parse_slot_content(rendered, parse_input)

      nil ->
        "<% #{partial_name} %>" <> content <> "<%/ #{partial_name} %>"
    end
  end

  defp parse_slot_content(content, parse_input) do
    slot_regex = ~r|<%\s*(.*?)\s*%>(.*?)<%/\s*\1\s*%>|s
    self_closing_regex = ~r|<%(.*?)%/>|

    content =
      case Regex.run(slot_regex, content, return: :index) do
        nil ->
          content

        _match ->
          Regex.replace(slot_regex, content, fn _full, name, slot_content ->
            render_partial(name, slot_content, parse_input)
          end)
      end

    result =
      Enum.reduce_while(
        Regex.scan(self_closing_regex, content, return: :index),
        %{out: "", cursor: 0},
        fn match, acc ->
          reduce_match(match, acc, %{parse_input | file: content})
        end
      )

    case result do
      {:error, _} -> content
      final -> final.out <> String.slice(content, final.cursor..-1//1)
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
