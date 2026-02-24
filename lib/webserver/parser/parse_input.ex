defmodule Webserver.Parser.ParseInput do
  @moduledoc """
  Holds all the input necessary to parse a template file.
  """

  @type t :: %__MODULE__{
          file: String.t(),
          partials: %{String.t() => String.t()},
          base_url: String.t()
        }

  defstruct [:file, :partials, :base_url]
end
