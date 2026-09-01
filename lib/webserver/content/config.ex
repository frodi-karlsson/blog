defmodule Webserver.Content.Config do
  @moduledoc """
  Store configuration held in `:persistent_term`, keyed by table name.

  Config is written once at store init and read on every request to check
  staleness, so it lives in `:persistent_term` rather than ETS — reads are a
  direct term lookup with no copy.

  `:persistent_term` writes trigger a global GC scan, so only write at init or
  on an explicit refresh. Never write per request.
  """

  @type t :: %{
          template_dir: String.t(),
          check_interval: non_neg_integer(),
          reader: module(),
          live_reload?: boolean()
        }

  @spec put(atom(), t()) :: :ok
  def put(table, %{} = config), do: :persistent_term.put(key(table), config)

  @spec get(atom()) :: t()
  def get(table), do: :persistent_term.get(key(table))

  @spec check_interval(atom()) :: non_neg_integer()
  def check_interval(table), do: get(table).check_interval

  @spec template_dir(atom()) :: String.t()
  def template_dir(table), do: get(table).template_dir

  @spec reader(atom()) :: module()
  def reader(table), do: get(table).reader

  defp key(table), do: {__MODULE__, table}
end
