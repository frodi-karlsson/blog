defmodule Webserver.Content.TableOwner do
  @moduledoc """
  Owns the content ETS table and nothing else.

  ETS tables die with the process that created them. `Store` does file I/O,
  template parsing, and content generation — all of which can crash — so it must
  not be the owner, or a single bad template takes the whole cache with it.

  This process holds no state and runs no logic, so there is nothing in it to
  crash. It exists purely to be the table's owner.
  """

  use GenServer

  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(table) when is_atom(table) do
    GenServer.start_link(__MODULE__, table, name: name_for(table))
  end

  @doc "Creates the table if it does not already exist. Safe to call repeatedly."
  @spec ensure_table(atom()) :: atom()
  def ensure_table(table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: :auto
        ])

      _ ->
        table
    end
  end

  defp name_for(table), do: :"#{table}.TableOwner"

  @impl true
  def init(table) do
    ensure_table(table)
    {:ok, table}
  end
end
