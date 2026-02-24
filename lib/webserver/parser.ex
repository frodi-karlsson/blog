defmodule Webserver.Parser do
  @moduledoc """
  Parses the custom HTML templating language, returning fully rendered HTML.
  """

  alias Webserver.Parser.{ParseInput, Resolver}

  @type parse_error ::
          {:ref_not_found, String.t()}
          | {:missing_slots, [String.t()]}
          | {:unexpected_slots, [String.t()]}

  @type parse_result :: {:ok, String.t()} | {:error, parse_error()}

  @self_closing_regex ~r|<%(.*?)%/>|
  @slot_regex ~r|<%\s*(.*?)\s*%>(.*?)<%/\s*\1\s*%>|s
  @named_slot_regex ~r|<slot:([a-z]+)>(.*?)</slot:\1>|s
  @slot_placeholder_regex ~r|\{\{([a-z]+)\}\}|

  @spec parse(ParseInput.t()) :: parse_result()
  def parse(parse_input) do
    start_time = System.monotonic_time()
    metadata = %{base_url: parse_input.base_url}

    :telemetry.execute(
      [:webserver, :parser, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
      case process_slots(parse_input.file, parse_input) do
        {:ok, processed_file} -> process_self_closing(processed_file, parse_input)
        error -> error
      end

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:webserver, :parser, :stop], %{duration: duration}, metadata)

    result
  end

  defp process_slots(file, parse_input) do
    case Regex.run(@slot_regex, file, return: :index) do
      nil ->
        {:ok, file}

      [{start, len}, {name_start, name_len}, {content_start, content_len}] ->
        name = binary_part(file, name_start, name_len)
        content = binary_part(file, content_start, content_len)

        case render_and_replace_slot(name, content, parse_input, file, start, len) do
          {:ok, processed} -> process_slots(processed, parse_input)
          error -> error
        end
    end
  end

  defp render_and_replace_slot(name, content, parse_input, file, start, len) do
    case render_partial(name, content, parse_input) do
      {:ok, rendered} ->
        prefix = if start > 0, do: binary_part(file, 0, start), else: ""
        suffix = binary_part(file, start + len, byte_size(file) - (start + len))
        {:ok, prefix <> rendered <> suffix}

      error ->
        error
    end
  end

  defp render_partial(name, raw_content, parse_input) do
    partial_name = String.trim(name)

    case Resolver.resolve_partial_reference(partial_name, parse_input) do
      partial when is_binary(partial) ->
        render_partial_with_slots(partial, raw_content, parse_input)

      nil ->
        {:error, {:ref_not_found, partial_name}}
    end
  end

  defp render_partial_with_slots(partial, raw_content, parse_input) do
    {_content, slot_map} = extract_named_slots(raw_content, parse_input)
    expected_slots = extract_expected_slots(partial)

    case validate_slots(expected_slots, slot_map) do
      :ok ->
        rendered = replace_slots(partial, slot_map, expected_slots)
        process_self_closing(rendered, parse_input)

      error ->
        error
    end
  end

  defp process_self_closing(content, parse_input) do
    result =
      @self_closing_regex
      |> Regex.scan(content, return: :index)
      |> Enum.reduce_while({0, ""}, fn
        [{start, len}, {name_start, name_len}], {cursor, acc} ->
          ref = content |> binary_part(name_start, name_len) |> String.trim()

          case Resolver.resolve_partial_reference(ref, parse_input) do
            nil ->
              {:halt, {:error, {:ref_not_found, ref}}}

            str when is_binary(str) ->
              {:cont, {start + len, acc <> binary_part(content, cursor, start - cursor) <> str}}
          end
      end)

    case result do
      {:error, _} = error ->
        error

      {cursor, acc} ->
        {:ok, acc <> binary_part(content, cursor, byte_size(content) - cursor)}
    end
  end

  defp extract_named_slots(content, parse_input) do
    case Regex.run(@named_slot_regex, content, return: :index) do
      nil ->
        {content, %{}}

      [{slot_start, slot_len}, {name_start, name_len}, {content_start, content_len}] ->
        slot_name = binary_part(content, name_start, name_len)
        slot_content = binary_part(content, content_start, content_len)

        processed =
          case process_slots(slot_content, parse_input) do
            {:ok, p} -> p
            {:error, _} -> slot_content
          end

        full_match = binary_part(content, slot_start, slot_len)
        new_content = String.replace(content, full_match, "{{#{slot_name}}}", global: false)

        {remaining, more_slots} = extract_named_slots(new_content, parse_input)
        {remaining, Map.put(more_slots, slot_name, processed)}
    end
  end

  defp extract_expected_slots(partial) do
    @slot_placeholder_regex
    |> Regex.scan(partial)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp validate_slots(expected, slot_map) do
    provided = slot_map |> Map.keys() |> MapSet.new()
    expected_set = MapSet.new(expected)

    missing = expected_set |> MapSet.difference(provided) |> MapSet.to_list()
    unexpected = provided |> MapSet.difference(expected_set) |> MapSet.to_list()

    cond do
      expected_set == provided -> :ok
      missing != [] -> {:error, {:missing_slots, missing}}
      true -> {:error, {:unexpected_slots, unexpected}}
    end
  end

  defp replace_slots(partial, slot_map, expected_slots) do
    Enum.reduce(expected_slots, partial, fn slot_name, acc ->
      case slot_map[slot_name] do
        content when is_binary(content) -> String.replace(acc, "{{#{slot_name}}}", content)
        nil -> acc
      end
    end)
  end
end
