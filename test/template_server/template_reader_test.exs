defmodule TemplateServer.TemplateReaderTest do
  use ExUnit.Case

  describe "get_partials with Sandbox" do
    test "should return partials for valid base_url" do
      {:ok, partials} = TemplateServer.TemplateReader.get_partials("/priv/templates")
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "should return error for invalid base_url" do
      result = TemplateServer.TemplateReader.get_partials("/invalid/path")
      assert result == {:error, {:enoent}}
    end
  end

  describe "read_page with Sandbox" do
    test "should read index page successfully" do
      {:ok, content} = TemplateServer.TemplateReader.read_page("/priv/templates", "index.html")
      assert is_binary(content)
    end

    test "should return error for missing page" do
      result = TemplateServer.TemplateReader.read_page("/priv/templates", "missing.html")
      assert result == {:error, {:not_found, "missing.html"}}
    end
  end

  describe "get_partials with File" do
    test "should read partials from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, partials} = TemplateServer.TemplateReader.File.get_partials(base_path)
      assert is_map(partials)
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "should return error for missing directory" do
      result = TemplateServer.TemplateReader.File.get_partials("/nonexistent")
      assert result == {:error, :enoent}
    end
  end

  describe "read_page with File" do
    test "should read page from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, content} = TemplateServer.TemplateReader.File.read_page(base_path, "index.html")
      assert is_binary(content)
    end

    test "should return error for missing page" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      result = TemplateServer.TemplateReader.File.read_page(base_path, "nonexistent.html")
      assert result == {:error, :enoent}
    end
  end
end
