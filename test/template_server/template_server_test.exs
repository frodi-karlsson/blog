defmodule TemplateServerTest do
  use ExUnit.Case
  doctest(TemplateServer)

  describe "init" do
    test "should fail with non-binary base_url" do
      result = TemplateServer.init(1)
      assert result == {:stop, {:invalid_base_url, 1}}
    end
  end
end
