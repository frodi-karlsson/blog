defmodule Mix.Tasks.Check do
  @moduledoc """
  Run all checks: formatting, linting, dialyzer, and tests.

  This replicates the CI check job locally.

  Usage:
    mix check
  """
  @shortdoc "Run all checks"

  use Mix.Task

  @impl true
  def run(_args) do
    IO.puts("Running format check...")
    mix_formats()

    IO.puts("\nRunning Credo...")
    mix_credo()

    IO.puts("\nRunning Dialyzer...")
    mix_dialyzer()

    IO.puts("\nRunning tests...")
    mix_test()

    IO.puts("\nAll checks passed!")
  end

  defp mix_formats do
    {_, 0} = System.cmd("mix", ["format", "--check-formatted"])
  end

  defp mix_credo do
    {_, 0} = System.cmd("mix", ["credo", "--strict"])
  end

  defp mix_dialyzer do
    {_output, 0} = System.cmd("mix", ["dialyzer"])
  end

  defp mix_test do
    {_, 0} = System.cmd("mix", ["test"])
  end
end
