defmodule Webserver do
  @moduledoc """
  OTP Application entry point. Starts the supervision tree:

    - `Webserver.TemplateServer.Cache` — GenServer cache for parsed templates
    - `Bandit` — HTTP server using `Webserver.Router` as the Plug handler
  """

  use Application

  def start(_start_type, _start_args) do
    port = Application.fetch_env!(:webserver, :port)
    template_dir = Application.fetch_env!(:webserver, :template_dir)
    mtime_check_interval = Application.fetch_env!(:webserver, :mtime_check_interval)
    reader = Application.fetch_env!(:webserver, :template_reader)
    live_reload? = Application.get_env(:webserver, :live_reload, false)

    children = [
      {Webserver.TemplateServer.Cache,
       {template_dir, mtime_check_interval, reader, live_reload?}},
      {Bandit, plug: Webserver.Router, scheme: :http, port: port}
    ]

    children =
      if live_reload? do
        children ++
          [
            Webserver.LiveReload.PubSub,
            {Task, fn -> start_sass() end},
            {Webserver.Watcher, {template_dir, live_reload?}}
          ]
      else
        children
      end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp start_sass do
    DartSass.run(:default, ~w(--watch))
  end
end
