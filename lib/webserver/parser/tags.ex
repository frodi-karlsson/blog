defmodule Webserver.Parser.Tags do
  @moduledoc """
  Extracts the next templating tag from a string.

  This module works on the substring that starts immediately after an opening
  `<%` and returns:

  - the parsed tag (`:self`, `:open`, or `:close`)
  - the remaining suffix after the closing delimiter (`%>` or `%/>`)
  """

  alias Webserver.Parser.Attrs

  @type tag ::
          {:self, String.t(), map()}
          | {:open, String.t(), map()}
          | {:close, String.t()}

  @spec next_tag(String.t()) :: {:ok, tag(), String.t()} | {:error, {:malformed_tag, String.t()}}
  def next_tag(rest_after_open) when is_binary(rest_after_open) do
    self_match = :binary.match(rest_after_open, "%/>")
    open_match = :binary.match(rest_after_open, "%>")

    case {self_match, open_match} do
      {:nomatch, :nomatch} ->
        {:error, {:malformed_tag, "missing closing %> or %/>"}}

      _ ->
        {idx, delim_len, self_closing?} = choose_tag_delimiter(self_match, open_match)
        {raw_tag, suffix_after_tag} = split_at_tag_close(rest_after_open, idx, delim_len)
        raw_tag = String.trim(raw_tag)

        if self_closing? do
          parse_self_closing_tag(raw_tag, suffix_after_tag)
        else
          parse_open_or_close_tag(raw_tag, suffix_after_tag)
        end
    end
  end

  defp split_at_tag_close(rest_after_open, idx, delim_len) do
    raw_tag = binary_part(rest_after_open, 0, idx)

    suffix_after_tag =
      binary_part(
        rest_after_open,
        idx + delim_len,
        byte_size(rest_after_open) - (idx + delim_len)
      )

    {raw_tag, suffix_after_tag}
  end

  defp parse_open_or_close_tag(raw_tag, suffix_after_tag) do
    case parse_tag(raw_tag) do
      {:ok, tag} -> {:ok, tag, suffix_after_tag}
      {:error, _} = error -> error
    end
  end

  defp choose_tag_delimiter(:nomatch, {idx, len}), do: {idx, len, false}
  defp choose_tag_delimiter({idx, len}, :nomatch), do: {idx, len, true}

  defp choose_tag_delimiter({idx1, len1}, {idx2, len2}) do
    if idx1 <= idx2 do
      {idx1, len1, true}
    else
      {idx2, len2, false}
    end
  end

  defp parse_self_closing_tag("", _suffix_after_tag), do: {:error, {:malformed_tag, "empty tag"}}

  defp parse_self_closing_tag(tag_str, suffix_after_tag) do
    if String.starts_with?(tag_str, "/") do
      {:error, {:malformed_tag, "closing tag cannot be self-closing"}}
    else
      with {:ok, name, attrs} <- parse_name_and_attrs(tag_str) do
        {:ok, {:self, name, attrs}, suffix_after_tag}
      end
    end
  end

  defp parse_tag(""), do: {:error, {:malformed_tag, "empty tag"}}

  defp parse_tag(tag_str) do
    if String.starts_with?(tag_str, "/") do
      name = tag_str |> String.trim_leading("/") |> String.trim() |> first_token()
      {:ok, {:close, name}}
    else
      with {:ok, name, attrs} <- parse_name_and_attrs(tag_str) do
        {:ok, {:open, name, attrs}}
      end
    end
  end

  defp first_token(str) do
    str
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  defp parse_name_and_attrs(str) do
    case String.split(str, ~r/\s+/, parts: 2, trim: true) do
      [] ->
        {:error, {:malformed_tag, "missing tag name"}}

      [name] ->
        {:ok, name, %{}}

      [name, attrs_str] ->
        case Attrs.parse(attrs_str) do
          {:ok, attrs} -> {:ok, name, attrs}
          {:error, _} = error -> error
        end
    end
  end
end
