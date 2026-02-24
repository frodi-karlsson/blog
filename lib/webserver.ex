defmodule Webserver do
  @moduledoc """
  Documentation for `Webserver`.
  """

  use Application

  def start(_start_type, _start_args) do
    port = Application.fetch_env!(:webserver, :port)
    base_url = Application.fetch_env!(:webserver, :base_url)
    mtime_check_interval = Application.fetch_env!(:webserver, :mtime_check_interval)

    children = [
      {Registry, name: TemplateServer.Registry, keys: :unique},
      {TemplateServer.Cache, {base_url, mtime_check_interval}},
      {Bandit, plug: Router, scheme: :http, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
