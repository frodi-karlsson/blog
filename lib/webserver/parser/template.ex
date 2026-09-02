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

  ## Semantic narrowings versus the pre-compilation renderer

  Segment-walk rendering does not re-parse anything after substitution, which
  removes three behaviours the old renderer had as a side effect of its
  trailing `render_tags/2` pass over the fully-substituted text. All three are
  no-ops on the current site — verified by a byte-for-byte diff of every
  rendered page against the pre-refactor output — but they are real semantic
  changes and are recorded here rather than left to be rediscovered later:

    1. **Metadata-sourced slot values are inserted verbatim.** Previously a
       slot value pulled from page metadata (front matter) was merged in
       unrendered and then parsed once by the old trailing `render_tags/2`
       call, so a metadata value containing `<% x %/>` would have expanded.
       Now it does not: metadata is treated as data, not template source.
       Today metadata is front-matter strings plus already-rendered tag chip
       HTML, neither of which contains template syntax, so this does not
       change any shipped page — and treating front matter as data is the
       safer behaviour regardless.
    2. **`{{@attr}}` inside a slot's *value* is no longer substituted.** The
       old `replace_attrs` pass ran after `replace_slots` over the combined
       text, so an attr placeholder reachable only via a substituted slot
       value would still be replaced. The segment walk substitutes attrs only
       where the compiled template declares an `{:attr, name}` segment
       directly in its own text. No shipped partial declares attrs at all, so
       this is unobserved in practice.
    3. **Already-rendered slot content is not parsed a second time.** The old
       renderer's trailing pass re-tokenised the entire fully-substituted
       page, meaning slot content was effectively parsed twice. The segment
       walk renders each slot's content once, when it is extracted, and never
       revisits it.
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
