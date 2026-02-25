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
    IO.puts("Ensuring dependencies are installed...")
    {_, 0} = System.cmd("pnpm", ["install"], into: IO.stream(:stdio, :line))

    IO.puts("\nLinting E2E code...")
    {_, 0} = System.cmd("pnpm", ["run", "lint"], into: IO.stream(:stdio, :line))

    IO.puts("\nChecking E2E code formatting...")

    {_, 0} =
      System.cmd("pnpm", ["run", "format", "--", "--check"], into: IO.stream(:stdio, :line))

    IO.puts("\nEnsuring Playwright browsers are installed...")

    install_args =
      if System.get_env("CI") do
        ["exec", "playwright", "install", "--with-deps", "chromium"]
      else
        ["exec", "playwright", "install", "chromium"]
      end

    {_, 0} = System.cmd("pnpm", install_args, into: IO.stream(:stdio, :line))

    IO.puts("\nRunning E2E tests...")
    {_, 0} = System.cmd("pnpm", ["exec", "playwright", "test"], into: IO.stream(:stdio, :line))
    IO.puts("\nE2E tests passed!")
  end
end
