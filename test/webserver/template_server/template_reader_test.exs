defmodule Webserver.TemplateServer.TemplateReaderTest do
  use ExUnit.Case

  alias Webserver.TemplateServer.TemplateReader.File, as: FileReader
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  describe "get_partials with Sandbox" do
    test "returns partials for valid base_url" do
      {:ok, partials} = Sandbox.get_partials("/priv/templates")
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "returns error for invalid base_url" do
      assert Sandbox.get_partials("/invalid/path") == {:error, :enoent}
    end
  end

  describe "read_page with Sandbox" do
    test "reads index page successfully" do
      {:ok, content} = Sandbox.read_page("/priv/templates", "index.html")
      assert is_binary(content)
    end

    test "returns error for missing page" do
      assert Sandbox.read_page("/priv/templates", "missing.html") ==
               {:error, {:not_found, "missing.html"}}
    end
  end

  describe "get_partials with File" do
    test "reads partials from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, partials} = FileReader.get_partials(base_path)
      assert is_map(partials)
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "returns error for missing directory" do
      assert FileReader.get_partials("/nonexistent") == {:error, :enoent}
    end
  end

  describe "read_page with File" do
    test "reads page from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, content} = FileReader.read_page(base_path, "index.html")
      assert is_binary(content)
    end

    test "returns error for missing page" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      assert FileReader.read_page(base_path, "nonexistent.html") == {:error, :enoent}
    end
  end
end
