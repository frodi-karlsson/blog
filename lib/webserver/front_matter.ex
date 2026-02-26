defmodule Webserver.FrontMatter do
  @moduledoc """
  Parses front-matter metadata from template files.

  Front-matter is delimited by `---` lines at the top of the file:

      ---
      title: My Page
      date: 2026-02-25
      ---
      <html>...</html>

  Keys are strings; values are strings. The boolean value `"true"` is not
  coerced — consumers are responsible for interpretation.
  """

  @type metadata :: %{String.t() => String.t()}

  @doc """
  Splits a file's raw content into front-matter metadata and body.

  Returns `{metadata, body}` where metadata is a map of string keys to string
  values. If no front-matter block is present, returns `{%{}, content}`.
  """
  @spec parse(String.t()) :: {metadata(), String.t()}
  def parse("---\n---\n" <> body), do: {%{}, body}

  def parse("---\n" <> rest) do
    case :binary.split(rest, "\n---\n") do
      [block, body] -> {parse_block(block), body}
      _ -> {%{}, "---\n" <> rest}
    end
  end

  def parse(content), do: {%{}, content}

  @doc "Returns true if the metadata represents a blog post (has `date` and `summary`)."
  @spec blog_post?(metadata()) :: boolean()
  def blog_post?(meta), do: Map.has_key?(meta, "date") and Map.has_key?(meta, "summary")

  @doc """
  Formats an ISO 8601 date string (`YYYY-MM-DD`) to a human-readable form.

  Returns the original string if parsing fails.

      iex> Webserver.FrontMatter.format_date("2026-02-25")
      "Feb 25, 2026"
  """
  @spec format_date(String.t()) :: String.t()
  def format_date(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} ->
        month = elem(months(), date.month - 1)
        "#{month} #{date.day}, #{date.year}"

      _ ->
        iso_date
    end
  end

  @doc """
  Derives a URL path from a page filename.

      iex> Webserver.FrontMatter.derive_path("index.html")
      "/"
      iex> Webserver.FrontMatter.derive_path("my-post.html")
      "/my-post"
      iex> Webserver.FrontMatter.derive_path("admin/design-system.html")
      "/admin/design-system"
  """
  @spec derive_path(String.t()) :: String.t()
  def derive_path(filename) do
    base = filename |> Path.rootname()

    case Path.basename(base) do
      "index" ->
        parent = Path.dirname(base)
        if parent == ".", do: "/", else: "/" <> parent

      _ ->
        "/" <> base
    end
  end

  defp parse_block(block) do
    block
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case :binary.split(line, ": ") do
        [key, value] when key != "" -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp months,
    do: {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
end
