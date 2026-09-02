defmodule Webserver.Parser.ParseInput do
  @moduledoc """
  Holds all the input necessary to parse a template file.
  """

  alias Webserver.Parser.Template

  @type t :: %__MODULE__{
          file: String.t(),
          partials: %{String.t() => String.t()},
          compiled_partials: %{String.t() => Template.t()},
          template_dir: String.t(),
          metadata: %{String.t() => any()},
          asset_resolver: module()
        }

  defstruct file: nil,
            partials: %{},
            compiled_partials: %{},
            template_dir: nil,
            metadata: %{},
            asset_resolver: Webserver.AssetServer
end
