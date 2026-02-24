defmodule Webserver do
  @moduledoc """
  Documentation for `Webserver`.
  """

  use Application

  def start(_start_type, _start_args) do
    port = Application.fetch_env!(:webserver, :port)
    base_url = Application.fetch_env!(:webserver, :base_url)

    children = [
      {TemplateServer.Cache, base_url},
      {Bandit, plug: Router, scheme: :http, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def start_template_server(_base_url) do
    # Kept for backward compatibility, but cache is now a singleton
    if Process.whereis(TemplateServer.Cache) do
      {:ok, Process.whereis(TemplateServer.Cache)}
    else
      {:error, :cache_not_started}
    end
  end
end
