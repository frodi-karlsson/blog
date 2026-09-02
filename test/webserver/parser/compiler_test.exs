defmodule Webserver.Parser.CompilerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Webserver.Parser.Compiler
  alias Webserver.Parser.Template

  defp compile!(text) do
    assert {:ok, %Template{} = template} = Compiler.compile(text)
    template
  end

  describe "literals" do
    test "a literal-only partial compiles to a single binary segment" do
      template = compile!("<div>hello</div>")

      assert template.segments == ["<div>hello</div>"]
      assert MapSet.to_list(template.slots) == []
      assert MapSet.to_list(template.attrs) == []
    end

    test "an empty partial compiles to no segments" do
      assert compile!("").segments == []
    end

    test "a placeholder that is neither a slot nor an attr stays literal" do
      template = compile!("{{NotASlot}}")

      assert template.segments == ["{{NotASlot}}"]
      assert MapSet.to_list(template.slots) == []
    end
  end

  describe "slots" do
    test "{{slot}} becomes a slot segment and is declared" do
      template = compile!("<p>{{slot}}</p>")

      assert template.segments == ["<p>", {:slot, "slot"}, "</p>"]
      assert MapSet.to_list(template.slots) == ["slot"]
    end

    test "a repeated slot produces a segment per occurrence but one declaration" do
      template = compile!("{{a}}|{{a}}")

      assert template.segments == [{:slot, "a"}, "|", {:slot, "a"}]
      assert MapSet.to_list(template.slots) == ["a"]
    end
  end

  describe "attrs" do
    test "{{@attr}} becomes an attr segment and is declared" do
      template = compile!(~S(<div class="{{@attr}}">))

      assert template.segments == [~S(<div class="), {:attr, "attr"}, ~S(">)]
      assert MapSet.to_list(template.attrs) == ["attr"]
      assert MapSet.to_list(template.slots) == []
    end

    test "slots and attrs interleave in source order" do
      template = compile!("<div class='{{@class}}'>{{default}}</div>")

      assert template.segments == [
               "<div class='",
               {:attr, "class"},
               "'>",
               {:slot, "default"},
               "</div>"
             ]

      assert MapSet.to_list(template.attrs) == ["class"]
      assert MapSet.to_list(template.slots) == ["default"]
    end
  end

  describe "asset placeholders" do
    test "{{+ /static/x.css}} stays in the literal text" do
      template = compile!(~S(<link href="{{+ /static/x.css}}">))

      assert template.segments == [~S(<link href="{{+ /static/x.css}}">)]
      assert MapSet.to_list(template.slots) == []
      assert MapSet.to_list(template.attrs) == []
    end
  end

  describe "nested partial references" do
    test "a self-closing reference becomes a partial segment" do
      template = compile!("a<% foo.html %/>b")

      assert template.segments == ["a", {:partial, "foo.html", %{}}, "b"]
    end

    test "a self-closing reference captures its attributes" do
      template = compile!(~S(<% foo.html title="Hi" n='2' %/>))

      assert template.segments == [{:partial, "foo.html", %{"title" => "Hi", "n" => "2"}}]
    end

    test "an open/close reference keeps its raw body" do
      template = compile!("<% foo.html %><slot:a>x</slot:a><%/ foo.html %>")

      assert template.segments == [{:partial_block, "foo.html", %{}, "<slot:a>x</slot:a>"}]
    end

    test "an open/close reference captures attributes and nests" do
      template = compile!("<% a.html k='v' %>1<% a.html %>2<%/ a.html %>3<%/ a.html %>")

      assert template.segments == [
               {:partial_block, "a.html", %{"k" => "v"}, "1<% a.html %>2<%/ a.html %>3"}
             ]
    end

    test "a reference sits between the literals surrounding it" do
      template = compile!("{{a}}<% foo.html %/>{{b}}")

      assert template.segments == [
               {:slot, "a"},
               {:partial, "foo.html", %{}},
               {:slot, "b"}
             ]
    end
  end

  describe "errors" do
    test "a tag with no closing delimiter is malformed" do
      assert Compiler.compile("<% foo.html") ==
               {:error, {:malformed_tag, "missing closing %> or %/>"}}
    end

    test "an empty tag is malformed" do
      assert Compiler.compile("<% %/>") == {:error, {:malformed_tag, "empty tag"}}
    end

    test "a stray closing tag is malformed" do
      assert Compiler.compile("<%/ foo.html %>") ==
               {:error, {:malformed_tag, "unexpected closing tag: foo.html"}}
    end

    test "a mismatched closing tag is malformed" do
      assert Compiler.compile("<% a.html %>x<%/ b.html %>") ==
               {:error, {:malformed_tag, "unexpected closing tag: b.html"}}
    end

    test "an open tag with no close is unclosed" do
      assert Compiler.compile("<% a.html %>x") == {:error, {:unclosed_tag, "a.html"}}
    end
  end

  describe "compile_all" do
    test "compiles every entry, keyed the same way" do
      compiled = Compiler.compile_all(%{"partials/a.html" => "{{x}}"})

      assert %{"partials/a.html" => %Template{segments: [{:slot, "x"}]}} = compiled
    end

    test "drops entries that fail to compile rather than raising" do
      compiled =
        Compiler.compile_all(%{"partials/bad.html" => "<% oops", "partials/ok.html" => ""})

      assert Map.keys(compiled) == ["partials/ok.html"]
    end

    test "logs a warning naming the partial and the error when one fails to compile" do
      log =
        capture_log(fn ->
          compiled =
            Compiler.compile_all(%{"partials/bad.html" => "<% oops", "partials/ok.html" => ""})

          refute Map.has_key?(compiled, "partials/bad.html")
        end)

      assert log =~ "partial_compile_failed"
      assert log =~ "partials/bad.html"
      assert log =~ "malformed_tag"
    end
  end
end
