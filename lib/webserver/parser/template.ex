defmodule Webserver.Parser.Template do
  @moduledoc """
  A partial compiled once into a flat segment list.

  Rendering walks `segments` accumulating iodata: no regex, no re-tokenising.
  `slots` and `attrs` are the declared names, computed at compile time.

  A `{:partial, name, attrs}` segment is a reference to another partial,
  resolved at render time. This replaces the old approach of re-parsing
  substituted partial text, which was the only mechanism resolving
  partial-inside-partial references.

  `{:partial_block, name, attrs, body}` is the same thing for the open/close
  form (`<% x.html %>...<%/ x.html %>`), whose body may declare `<slot:...>`
  blocks. No partial shipped with the site uses that form from inside another
  partial, so the body is kept as raw text and rendered through the ordinary
  text path rather than being compiled. Supporting it structurally would mean
  a recursive per-slot segment list for a shape that does not occur.
  """

  defstruct segments: [], slots: MapSet.new(), attrs: MapSet.new()

  @type segment ::
          binary()
          | {:slot, String.t()}
          | {:attr, String.t()}
          | {:partial, String.t(), map()}
          | {:partial_block, String.t(), map(), String.t()}

  @type t :: %__MODULE__{
          segments: [segment()],
          slots: MapSet.t(String.t()),
          attrs: MapSet.t(String.t())
        }
end
