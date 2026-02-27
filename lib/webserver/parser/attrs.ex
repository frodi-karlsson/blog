defmodule Webserver.Parser.Attrs do
  @moduledoc """
  Parses tag attributes for the templating language.

  Supports syntax like:

      key="value" key='value' key=unquoted

  Returns a map of string keys to string values.
  """

  @type attrs :: %{optional(String.t()) => String.t()}

  @spec parse(String.t()) :: {:ok, attrs()} | {:error, {:malformed_tag, String.t()}}
  def parse(attrs_str) when is_binary(attrs_str) do
    attrs_str = String.trim(attrs_str)

    if attrs_str == "" do
      {:ok, %{}}
    else
      do_parse(attrs_str, %{})
    end
  end

  defp do_parse(<<>>, acc), do: {:ok, acc}

  defp do_parse(str, acc) do
    str = String.trim_leading(str)

    if str == "" do
      {:ok, acc}
    else
      with {:ok, key, rest} <- parse_key(str),
           {:ok, val, rest} <- parse_value(rest) do
        do_parse(rest, Map.put(acc, key, val))
      end
    end
  end

  defp parse_key(str) do
    case Regex.run(~r/^([a-zA-Z_][a-zA-Z0-9_\-]*)\s*=\s*(.*)$/s, str) do
      [_, key, rest] ->
        {:ok, key, rest}

      _ ->
        {:error, {:malformed_tag, "invalid attribute syntax"}}
    end
  end

  defp parse_value(<<quote::binary-size(1), rest::binary>>) when quote in ["\"", "'"] do
    case String.split(rest, quote, parts: 2) do
      [_, _] = parts ->
        [val, rest_after_value] = parts
        {:ok, val, rest_after_value}

      [_] ->
        {:error, {:malformed_tag, "unterminated quoted attribute"}}
    end
  end

  defp parse_value(str) do
    case String.split(str, ~r/\s+/, parts: 2) do
      [val] -> {:ok, val, ""}
      [val, rest] -> {:ok, val, rest}
      _ -> {:error, {:malformed_tag, "missing attribute value"}}
    end
  end
end
