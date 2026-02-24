defmodule TemplateServer.TemplateReaderTest do
  use ExUnit.Case
  doctest(TemplateServer.TemplateReader)

  describe "Sandbox.get_partials" do
    test "should return partials for valid base_url" do
      result = TemplateServer.TemplateReader.Sandbox.get_partials("/priv/templates")
      {:ok, partials} = result
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "should return error for invalid base_url" do
      result = TemplateServer.TemplateReader.Sandbox.get_partials("/invalid/path")
      assert result == {:error, {:enoent}}
    end
  end

  describe "Sandbox.read_page" do
    test "should read index page successfully" do
      result = TemplateServer.TemplateReader.Sandbox.read_page("/priv/templates", "index.html")
      {:ok, content} = result
      assert is_binary(content)
    end

    test "should return error for missing page" do
      result = TemplateServer.TemplateReader.Sandbox.read_page("/priv/templates", "missing.html")
      assert result == {:error, {:not_found, "missing.html"}}
    end
  end

  describe "File.get_partials" do
    setup do
      base_path = :code.priv_dir(:webserver) |> to_string()
      {:ok, base_path: Path.join(base_path, "templates")}
    end

    test "should read partials from filesystem", %{base_path: base_path} do
      result = TemplateServer.TemplateReader.File.get_partials(base_path)
      {:ok, partials} = result
      assert is_map(partials)
      assert Map.has_key?(partials, "partials/head.html")
    end

    test "should return error for missing directory", %{base_path: _base_path} do
      result = TemplateServer.TemplateReader.File.get_partials("/nonexistent")
      assert result == {:error, :enoent}
    end
  end

  describe "File.read_page" do
    setup do
      base_path = :code.priv_dir(:webserver) |> to_string()
      {:ok, base_path: Path.join(base_path, "templates")}
    end

    test "should read page from filesystem", %{base_path: base_path} do
      result = TemplateServer.TemplateReader.File.read_page(base_path, "index.html")
      {:ok, content} = result
      assert is_binary(content)
    end

    test "should return error for missing page", %{base_path: base_path} do
      result = TemplateServer.TemplateReader.File.read_page(base_path, "nonexistent.html")
      assert result == {:error, :enoent}
    end
  end
end
