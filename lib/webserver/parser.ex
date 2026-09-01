defmodule Webserver.Parser do
  @moduledoc """
  Parses the custom HTML templating language, returning fully rendered HTML.
  """

  alias Webserver.Parser.{Compiler, Img, ParseInput, Resolver, Tags, Template}

  @type parse_error ::
          {:ref_not_found, String.t()}
          | {:missing_slots, [String.t()]}
          | {:missing_attrs, [String.t()]}
          | {:unexpected_slots, [String.t()]}
          | {:unresolved_asset, String.t()}
          | {:unresolved_image_meta, String.t()}
          | {:non_image_src, String.t()}
          | {:malformed_tag, String.t()}
          | {:unclosed_tag, String.t()}

  @type parse_result :: {:ok, String.t()} | {:error, parse_error()}

  @named_slot_regex ~r|<slot:([a-z_]+)>(.*?)</slot:\1>|s
  @asset_placeholder_regex ~r|\{\{\+\s*([^}]+?)\s*\}\}|

  @asset_tag_deprecation "asset tag is no longer supported; use {{+ /static/...}}"

  @spec parse(ParseInput.t()) :: parse_result()
  def parse(parse_input) do
    start_time = System.monotonic_time()
    metadata = %{template_dir: parse_input.template_dir}

    :telemetry.execute(
      [:webserver, :parser, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result = render_tags(parse_input.file, parse_input)

    duration = System.monotonic_time() - start_time
    :telemetry.execute([:webserver, :parser, :stop], %{duration: duration}, metadata)

    result
  end

  defp render_tags(content, %ParseInput{} = parse_input) when is_binary(content) do
    with {:ok, rendered_iodata, rest} <- render_until(content, parse_input, nil, []) do
      if rest == "" do
        rendered = IO.iodata_to_binary(rendered_iodata)
        resolve_asset_placeholders(rendered, parse_input)
      else
        {:error, {:malformed_tag, "unexpected trailing content"}}
      end
    end
  end

  defp render_until(content, %ParseInput{} = parse_input, stop_name, acc)
       when is_binary(content) and is_list(acc) do
    case :binary.match(content, "<%") do
      :nomatch ->
        render_until_no_more_tags(content, stop_name, acc)

      {idx, 2} ->
        {prefix, rest} = split_at_open_tag(content, idx)

        with {:ok, tag, suffix_after_tag} <- Tags.next_tag(rest) do
          process_tag(tag, prefix, suffix_after_tag, parse_input, stop_name, acc)
        end
    end
  end

  defp render_until_no_more_tags(content, stop_name, acc) do
    if is_nil(stop_name) do
      {:ok, [acc, content], ""}
    else
      {:error, {:unclosed_tag, stop_name}}
    end
  end

  defp split_at_open_tag(content, idx) do
    prefix = binary_part(content, 0, idx)
    rest = binary_part(content, idx + 2, byte_size(content) - (idx + 2))
    {prefix, rest}
  end

  defp process_tag({:close, name}, prefix, suffix_after_tag, _parse_input, stop_name, acc) do
    if stop_name == name do
      {:ok, [acc, prefix], suffix_after_tag}
    else
      {:error, {:malformed_tag, "unexpected closing tag: #{name}"}}
    end
  end

  defp process_tag({:self, name, attrs}, prefix, suffix_after_tag, parse_input, stop_name, acc) do
    with {:ok, replacement} <- render_self_tag(name, attrs, parse_input) do
      render_until(suffix_after_tag, parse_input, stop_name, [acc, prefix, replacement])
    end
  end

  defp process_tag({:open, name, attrs}, prefix, suffix_after_tag, parse_input, stop_name, acc) do
    with {:ok, rendered_body, rest_after_close} <-
           render_until(suffix_after_tag, parse_input, name, []),
         {:ok, replacement} <-
           rendered_body
           |> IO.iodata_to_binary()
           |> then(&render_open_tag(name, attrs, &1, parse_input)) do
      render_until(rest_after_close, parse_input, stop_name, [acc, prefix, replacement])
    end
  end

  defp render_self_tag("asset", _attrs, _parse_input) do
    {:error, {:malformed_tag, @asset_tag_deprecation}}
  end

  defp render_self_tag("img", attrs, parse_input) do
    with {:ok, iodata} <- Img.render(attrs, parse_input) do
      {:ok, IO.iodata_to_binary(iodata)}
    end
  end

  defp render_self_tag(name, attrs, parse_input) do
    render_partial(name, "", attrs, parse_input)
  end

  defp render_open_tag("asset", _attrs, _body, _parse_input) do
    {:error, {:malformed_tag, @asset_tag_deprecation}}
  end

  defp render_open_tag("img", _attrs, _body, _parse_input) do
    {:error, {:malformed_tag, "img tag must be self-closing"}}
  end

  defp render_open_tag(name, attrs, body, parse_input) do
    render_partial(name, body, attrs, parse_input)
  end

  defp render_partial(name, raw_content, attrs, parse_input) do
    partial_name = String.trim(name)

    with {:ok, %Template{} = template} <- fetch_template(partial_name, parse_input) do
      render_template(template, raw_content, attrs, parse_input)
    end
  end

  # Compiled templates are published at load time. A `ParseInput` built by hand
  # (generators, tests) carries only the raw partial text, so compile on demand
  # rather than making the compiled map mandatory.
  defp fetch_template(name, parse_input) do
    key = Resolver.partial_key(name)

    case Map.fetch(parse_input.compiled_partials, key) do
      {:ok, %Template{} = template} -> {:ok, template}
      :error -> compile_partial(key, name, parse_input)
    end
  end

  defp compile_partial(key, name, parse_input) do
    case Map.fetch(parse_input.partials, key) do
      {:ok, text} -> Compiler.compile(text)
      :error -> {:error, {:ref_not_found, name}}
    end
  end

  defp render_template(%Template{} = template, raw_content, attrs, parse_input) do
    case extract_named_slots(raw_content, parse_input) do
      {:ok, slot_map} ->
        expected_slots = MapSet.to_list(template.slots)
        slot_map = merge_metadata_slots(slot_map, expected_slots, parse_input.metadata)
        expected_attrs = MapSet.to_list(template.attrs)

        with :ok <- validate_slots(expected_slots, slot_map),
             :ok <- validate_attrs(expected_attrs, attrs) do
          render_segments(template.segments, slot_map, attrs, parse_input, [])
        end

      error ->
        error
    end
  end

  defp render_segments([], _slot_map, _attrs, _parse_input, acc),
    do: {:ok, IO.iodata_to_binary(acc)}

  defp render_segments([segment | rest], slot_map, attrs, parse_input, acc) do
    with {:ok, rendered} <- render_segment(segment, slot_map, attrs, parse_input) do
      render_segments(rest, slot_map, attrs, parse_input, [acc, rendered])
    end
  end

  defp render_segment(literal, _slot_map, _attrs, _parse_input) when is_binary(literal),
    do: {:ok, literal}

  defp render_segment({:slot, name}, slot_map, _attrs, _parse_input),
    do: {:ok, Map.fetch!(slot_map, name)}

  defp render_segment({:attr, name}, _slot_map, attrs, _parse_input),
    do: {:ok, Map.fetch!(attrs, name)}

  # This is the invariant the old post-substitution `render_tags/2` call
  # existed to preserve: a partial referenced from inside another partial
  # (layout.html -> header_assets.html -> generated_livereload_script.html)
  # is resolved here, structurally, instead of by re-tokenising spliced text.
  defp render_segment({:partial, name, tag_attrs}, _slot_map, _attrs, parse_input),
    do: render_self_tag(name, tag_attrs, parse_input)

  # No shipped partial references another partial in open/close form, so the
  # body is kept as text and rendered through the ordinary path.
  defp render_segment({:partial_block, name, tag_attrs, body}, _slot_map, _attrs, parse_input) do
    with {:ok, rendered_body, _rest} <- render_until(body, parse_input, nil, []) do
      rendered_body
      |> IO.iodata_to_binary()
      |> then(&render_open_tag(name, tag_attrs, &1, parse_input))
    end
  end

  defp merge_metadata_slots(slot_map, expected, metadata) do
    Enum.reduce(expected, slot_map, &do_merge_metadata_slot(&1, &2, metadata))
  end

  defp do_merge_metadata_slot(name, acc, metadata) do
    if Map.has_key?(acc, name) do
      acc
    else
      metadata |> Map.get(name) |> maybe_put_slot(acc, name)
    end
  end

  defp maybe_put_slot(nil, acc, _name), do: acc
  defp maybe_put_slot(val, acc, name), do: Map.put(acc, name, to_string(val))

  defp resolve_asset_placeholders(content, parse_input) do
    matches = Regex.scan(@asset_placeholder_regex, content, return: :index)

    if matches == [] do
      {:ok, content}
    else
      with {:ok, rendered_iodata} <-
             resolve_asset_placeholder_matches(content, matches, parse_input) do
        {:ok, IO.iodata_to_binary(rendered_iodata)}
      end
    end
  end

  defp resolve_asset_placeholder_matches(content, matches, parse_input)
       when is_binary(content) and is_list(matches) do
    result =
      Enum.reduce_while(matches, {0, []}, fn
        [{full_start, full_len}, {path_start, path_len}], {cursor, acc} ->
          prefix = binary_part(content, cursor, full_start - cursor)

          path =
            content
            |> binary_part(path_start, path_len)
            |> String.trim()
            |> strip_wrapping_quotes()

          case resolve_asset(path, parse_input) do
            {:ok, resolved} ->
              {:cont, {full_start + full_len, [acc, prefix, resolved]}}

            {:error, _} = error ->
              {:halt, error}
          end
      end)

    case result do
      {:error, _} = error ->
        error

      {cursor, iodata} when is_integer(cursor) ->
        suffix = binary_part(content, cursor, byte_size(content) - cursor)
        {:ok, [iodata, suffix]}
    end
  end

  defp resolve_asset(path, %ParseInput{} = parse_input) do
    if Application.get_env(:webserver, :live_reload, false) do
      {:ok, path}
    else
      case parse_input.asset_resolver.resolve(path) do
        {:ok, resolved} -> {:ok, resolved}
        {:error, :not_found} -> {:error, {:unresolved_asset, path}}
      end
    end
  end

  defp strip_wrapping_quotes(<<q::binary-size(1), rest::binary>>) when q in ["\"", "'"] do
    if String.ends_with?(rest, q) and byte_size(rest) >= 1 do
      String.trim_trailing(rest, q)
    else
      q <> rest
    end
  end

  defp strip_wrapping_quotes(other), do: other

  defp extract_named_slots(content, parse_input) when is_binary(content) do
    @named_slot_regex
    |> Regex.scan(content, return: :index)
    |> Enum.reduce_while({:ok, %{}}, fn
      [_full, {name_start, name_len}, {inner_start, inner_len}], {:ok, slots} ->
        slot_name = binary_part(content, name_start, name_len)
        slot_content = binary_part(content, inner_start, inner_len)

        case render_tags(slot_content, parse_input) do
          # Earlier declarations win, matching the previous recursive extraction.
          {:ok, processed} -> {:cont, {:ok, Map.put_new(slots, slot_name, processed)}}
          {:error, _} = error -> {:halt, error}
        end
    end)
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

  defp validate_attrs(expected, attrs) do
    provided = attrs |> Map.keys() |> MapSet.new()
    expected_set = MapSet.new(expected)
    missing = expected_set |> MapSet.difference(provided) |> MapSet.to_list()

    if missing == [] do
      :ok
    else
      {:error, {:missing_attrs, missing}}
    end
  end
end
