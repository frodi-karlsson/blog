defmodule Webserver do
  @moduledoc """
  OTP Application entry point. Starts the supervision tree:

    - `Webserver.TemplateServer.Cache` — GenServer cache for parsed templates
    - `Bandit` — HTTP server using `Webserver.Router` as the Plug handler
  """

  use Application

  def start(_start_type, _start_args) do
    port = Application.fetch_env!(:webserver, :port)
    base_url = Application.fetch_env!(:webserver, :base_url)
    mtime_check_interval = Application.fetch_env!(:webserver, :mtime_check_interval)
    reader = Application.fetch_env!(:webserver, :template_reader)

    children = [
      {Webserver.TemplateServer.Cache, {base_url, mtime_check_interval, reader}},
      {Bandit, plug: Webserver.Router, scheme: :http, port: port}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
