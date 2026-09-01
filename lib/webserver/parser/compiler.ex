defmodule Webserver.Parser.Compiler do
  @moduledoc """
  Compiles a partial's text into a `Webserver.Parser.Template` once, at load
  time, so rendering it is a walk over a segment list rather than a fresh
  tokenising pass plus two `Regex.replace/4` passes per render.

  Tokenising reuses `Webserver.Parser.Tags.next_tag/1`, so the accepted syntax
  and every error tuple are the parser's, not a second dialect.
  """

  alias Webserver.Parser
  alias Webserver.Parser.PartialMeta
  alias Webserver.Parser.Tags
  alias Webserver.Parser.Template

  # Slot and attr placeholders only. Asset placeholders (`{{+ ...}}`) stay in
  # the literal text: they are resolved by a pass over the fully rendered page,
  # not during the segment walk.
  @placeholder_regex ~r/\{\{@[a-zA-Z0-9_\-]+\}\}|\{\{[a-z_]+\}\}/

  @spec compile(String.t()) :: {:ok, Template.t()} | {:error, Parser.parse_error()}
  def compile(text) when is_binary(text) do
    case scan(text, 0, []) do
      {:ok, segments} ->
        meta = PartialMeta.build(text)
        {:ok, %Template{segments: segments, slots: meta.slots, attrs: meta.attrs}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Compiles every partial in a `key => text` map.

  Partials that fail to compile are omitted rather than raising: the parser
  falls back to compiling on demand, which surfaces the same error to whoever
  actually renders the broken partial, exactly as before.
  """
  @spec compile_all(%{String.t() => String.t()}) :: %{String.t() => Template.t()}
  def compile_all(partials) do
    for {key, text} <- partials, {:ok, template} <- [compile(text)], into: %{} do
      {key, template}
    end
  end

  defp scan(content, offset, acc) do
    case next_open(content, offset) do
      :nomatch ->
        {:ok, acc |> prepend_text(slice(content, offset)) |> Enum.reverse()}

      {idx, _} ->
        acc = prepend_text(acc, binary_part(content, offset, idx - offset))

        with {:ok, tag, suffix} <- Tags.next_tag(slice(content, idx + 2)) do
          scan_tag(tag, content, byte_size(content) - byte_size(suffix), acc)
        end
    end
  end

  defp scan_tag({:close, name}, _content, _offset, _acc) do
    {:error, {:malformed_tag, "unexpected closing tag: #{name}"}}
  end

  defp scan_tag({:self, name, attrs}, content, offset, acc) do
    scan(content, offset, [{:partial, name, attrs} | acc])
  end

  defp scan_tag({:open, name, attrs}, content, offset, acc) do
    with {:ok, body_end, after_close} <- find_close(content, offset, name) do
      body = binary_part(content, offset, body_end - offset)
      scan(content, after_close, [{:partial_block, name, attrs, body} | acc])
    end
  end

  # Returns the offset where the body ends and the offset just past the
  # matching close tag, mirroring how `render_until/4` pairs tags.
  defp find_close(content, offset, stop_name) do
    case next_open(content, offset) do
      :nomatch ->
        {:error, {:unclosed_tag, stop_name}}

      {idx, _} ->
        with {:ok, tag, suffix} <- Tags.next_tag(slice(content, idx + 2)) do
          skip_tag(tag, content, idx, byte_size(content) - byte_size(suffix), stop_name)
        end
    end
  end

  defp skip_tag({:close, name}, _content, idx, after_tag, stop_name) do
    if name == stop_name do
      {:ok, idx, after_tag}
    else
      {:error, {:malformed_tag, "unexpected closing tag: #{name}"}}
    end
  end

  defp skip_tag({:self, _name, _attrs}, content, _idx, after_tag, stop_name) do
    find_close(content, after_tag, stop_name)
  end

  defp skip_tag({:open, name, _attrs}, content, _idx, after_tag, stop_name) do
    with {:ok, _body_end, after_close} <- find_close(content, after_tag, name) do
      find_close(content, after_close, stop_name)
    end
  end

  defp next_open(content, offset) do
    :binary.match(content, "<%", scope: {offset, byte_size(content) - offset})
  end

  defp slice(content, offset), do: binary_part(content, offset, byte_size(content) - offset)

  # Splits a run of literal text into binaries and slot/attr segments,
  # prepending them to the reversed accumulator.
  defp prepend_text(acc, ""), do: acc

  defp prepend_text(acc, text) do
    {cursor, acc} =
      @placeholder_regex
      |> Regex.scan(text, return: :index)
      |> Enum.reduce({0, acc}, fn [{start, len}], {cursor, acc} ->
        acc = prepend_literal(acc, binary_part(text, cursor, start - cursor))
        {start + len, [placeholder(binary_part(text, start, len)) | acc]}
      end)

    prepend_literal(acc, binary_part(text, cursor, byte_size(text) - cursor))
  end

  defp prepend_literal(acc, ""), do: acc
  defp prepend_literal(acc, literal), do: [literal | acc]

  defp placeholder(<<"{{@", rest::binary>>),
    do: {:attr, binary_part(rest, 0, byte_size(rest) - 2)}

  defp placeholder(<<"{{", rest::binary>>),
    do: {:slot, binary_part(rest, 0, byte_size(rest) - 2)}
end
