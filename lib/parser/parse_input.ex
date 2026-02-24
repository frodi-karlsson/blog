defmodule Parser.ParseInput do
  @moduledoc """
  Holds all the input necessary to parse a file
  """

  defstruct [:file, :partials, :base_url]
end
