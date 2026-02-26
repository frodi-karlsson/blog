defmodule Webserver.Parser.ParseInput do
  @moduledoc """
  Holds all the input necessary to parse a template file.
  """

  @type t :: %__MODULE__{
          file: String.t(),
          partials: %{String.t() => String.t()},
          template_dir: String.t(),
          metadata: %{String.t() => any()}
        }

  defstruct file: nil, partials: %{}, template_dir: nil, metadata: %{}
end
