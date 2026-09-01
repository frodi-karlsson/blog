defmodule Webserver.Content.GeneratorTest do
  use ExUnit.Case, async: true

  alias Webserver.Content.Generator
  alias Webserver.Content.Post

  describe "build_posts_db/1" do
    test "filters out pages missing date or summary" do
      pages_meta = [
        {"index.html", %{"title" => "Home"}},
        {"a.html", %{"date" => "2026-01-01", "title" => "A", "summary" => "s"}},
        {"b.html", %{"date" => "2026-01-02", "title" => "B"}},
        {"c.html", %{"summary" => "s", "title" => "C"}}
      ]

      posts = Generator.build_posts_db(pages_meta)
      assert Enum.map(posts, & &1.id) == ["a"]
    end

    test "sorts posts by date descending" do
      pages_meta = [
        {"old.html", %{"date" => "2025-06-01", "summary" => "s", "title" => "Old"}},
        {"new.html", %{"date" => "2026-06-01", "summary" => "s", "title" => "New"}},
        {"mid.html", %{"date" => "2025-12-01", "summary" => "s", "title" => "Mid"}}
      ]

      posts = Generator.build_posts_db(pages_meta)
      assert Enum.map(posts, & &1.id) == ["new", "mid", "old"]
    end

    test "parses tags into lowercased list" do
      pages_meta = [
        {"a.html",
         %{
           "date" => "2026-01-01",
           "summary" => "s",
           "title" => "A",
           "tags" => "Anabranch, TypeScript"
         }}
      ]

      [post] = Generator.build_posts_db(pages_meta)
      assert post.tags == ["anabranch", "typescript"]
    end

    test "defaults tags to empty list when key is missing" do
      pages_meta = [
        {"a.html", %{"date" => "2026-01-01", "summary" => "s", "title" => "A"}}
      ]

      [post] = Generator.build_posts_db(pages_meta)
      assert post.tags == []
    end

    test "populates path from meta or derived filename" do
      pages_meta = [
        {"a.html", %{"date" => "2026-01-01", "summary" => "s", "title" => "A"}},
        {"b.html",
         %{"date" => "2026-01-01", "summary" => "s", "title" => "B", "path" => "/custom-b"}}
      ]

      posts = Generator.build_posts_db(pages_meta) |> Enum.sort_by(& &1.id)
      assert Enum.at(posts, 0).path == "/a"
      assert Enum.at(posts, 1).path == "/custom-b"
    end

    test "drops posts with malformed date and logs a warning" do
      import ExUnit.CaptureLog

      pages_meta = [
        {"bad.html", %{"date" => "not-a-date", "summary" => "s", "title" => "Bad"}},
        {"good.html", %{"date" => "2026-01-01", "summary" => "s", "title" => "Good"}}
      ]

      log =
        capture_log(fn ->
          posts = Generator.build_posts_db(pages_meta)
          assert Enum.map(posts, & &1.id) == ["good"]
        end)

      assert log =~ "post_build_failed"
    end

    test "populates all Post fields" do
      pages_meta = [
        {"a.html",
         %{
           "date" => "2026-05-04",
           "title" => "A",
           "summary" => "sum",
           "tags" => "typescript, anabranch",
           "canonical" => "https://example.com/a",
           "noindex" => "true"
         }}
      ]

      [post] = Generator.build_posts_db(pages_meta)
      assert post.id == "a"
      assert post.filename == "a.html"
      assert post.path == "/a"
      assert post.title == "A"
      assert post.date == ~D[2026-05-04]
      assert post.summary == "sum"
      assert post.tags == ["typescript", "anabranch"]
      assert post.canonical == "https://example.com/a"
      assert post.noindex == true
      assert %Post{} = post
    end
  end
end
