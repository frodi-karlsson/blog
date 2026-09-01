defmodule Webserver.Parser.ParseInput do
  @moduledoc """
  Holds all the input necessary to parse a template file.
  """

  alias Webserver.Parser.PartialMeta

  @type t :: %__MODULE__{
          file: String.t(),
          partials: %{String.t() => String.t()},
          partial_meta: %{String.t() => PartialMeta.t()},
          template_dir: String.t(),
          metadata: %{String.t() => any()},
          asset_resolver: module()
        }

  defstruct file: nil,
            partials: %{},
            partial_meta: %{},
            template_dir: nil,
            metadata: %{},
            asset_resolver: Webserver.AssetServer
end
