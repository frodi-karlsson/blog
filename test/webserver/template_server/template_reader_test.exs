defmodule Webserver.TemplateServer.TemplateReaderTest do
  use ExUnit.Case, async: true

  alias Webserver.TemplateServer.TemplateReader.File, as: FileReader
  alias Webserver.TemplateServer.TemplateReader.Sandbox

  describe "get_partials with Sandbox" do
    test "should return partials for valid template_dir" do
      {:ok, partials} = Sandbox.get_partials("/priv/templates")
      assert Map.has_key?(partials, "partials/layout.html")
    end

    test "should return error for invalid template_dir" do
      assert Sandbox.get_partials("/invalid/path") == {:error, :not_found}
    end
  end

  describe "list_pages with Sandbox" do
    test "should return page filenames for valid template_dir" do
      {:ok, pages} = Sandbox.list_pages("/priv/templates")
      assert is_list(pages)
      assert "index.html" in pages
      assert "bespoke-elixir-web-framework.html" in pages
    end

    test "should return error for invalid template_dir" do
      assert Sandbox.list_pages("/invalid/path") == {:error, :not_found}
    end
  end

  describe "list_pages with File" do
    test "should return page filenames from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, pages} = FileReader.list_pages(base_path)
      assert is_list(pages)
      assert "index.html" in pages
      assert "bespoke-elixir-web-framework.html" in pages
    end

    test "should return nested page filenames" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, pages} = FileReader.list_pages(base_path)
      assert Enum.any?(pages, &String.contains?(&1, "/"))
    end
  end

  describe "read_page with Sandbox" do
    test "should read index page successfully" do
      {:ok, content} = Sandbox.read_page("/priv/templates", "index.html")
      assert is_binary(content)
    end

    test "should return error for missing page" do
      assert Sandbox.read_page("/priv/templates", "missing.html") == {:error, :not_found}
    end
  end

  describe "get_partials with File" do
    test "should read partials from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, partials} = FileReader.get_partials(base_path)
      assert is_map(partials)
      assert Map.has_key?(partials, "partials/layout.html")
    end

    test "should return error for missing directory" do
      assert FileReader.get_partials("/nonexistent") == {:error, :enoent}
    end
  end

  describe "read_page with File" do
    test "should read page from filesystem" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      {:ok, content} = FileReader.read_page(base_path, "index.html")
      assert is_binary(content)
    end

    test "should return error for missing page" do
      base_path = :code.priv_dir(:webserver) |> to_string() |> Path.join("templates")
      assert FileReader.read_page(base_path, "nonexistent.html") == {:error, :not_found}
    end
  end
end
