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
    run_step("format check", "mix", ["format", "--check-formatted"])
    run_step("Credo", "mix", ["credo", "--strict"])
    run_step("Dialyzer", "mix", ["dialyzer"])
    run_step("tests", "mix", ["test"])

    IO.puts("\nAll checks passed!")
  end

  defp run_step(label, cmd, args) do
    IO.puts("\nRunning #{label}...")
    {output, code} = System.cmd(cmd, args, stderr_to_stdout: true)

    if code != 0 do
      IO.puts(output)
      Mix.raise("#{label} failed (exit code #{code})")
    end
  end
end
