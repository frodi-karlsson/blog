defmodule Mix.Tasks.E2e do
  @moduledoc """
  Run Playwright end-to-end tests.

  Usage:
    mix e2e
  """
  @shortdoc "Run E2E tests"

  use Mix.Task

  @impl true
  def run(_args) do
    run_step("dependencies install", "pnpm", ["install"])
    run_step("E2E lint", "pnpm", ["run", "lint"])
    run_step("E2E format check", "pnpm", ["run", "format", "--", "--check"])

    install_args =
      if System.get_env("CI") do
        ["exec", "playwright", "install", "--with-deps", "chromium"]
      else
        ["exec", "playwright", "install", "chromium"]
      end

    run_step("Playwright browser install", "pnpm", install_args)
    run_step("E2E tests", "pnpm", ["exec", "playwright", "test"])

    IO.puts("\nE2E tests passed!")
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
