defmodule Webserver.Content.PageEntry do
  @moduledoc """
  One cached page: rendered HTML, the source file's mtime (or `:generated` for
  pages with no file behind them), and when it was last checked for staleness.
  """
  defstruct [:parsed, :mtime, :last_checked_at]

  @type t :: %__MODULE__{
          parsed: String.t(),
          mtime: :calendar.datetime() | nil | :generated,
          last_checked_at: integer()
        }
end
