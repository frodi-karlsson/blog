defmodule Webserver do
  @moduledoc """
  Documentation for `Webserver`.
  """

  use Application

  def start(_start_type, _start_args) do
    port = Application.fetch_env!(:webserver, :port)

    Supervisor.start_link(
      [
        {DynamicSupervisor, name: Webserver.TemplateServerSupervisor, strategy: :one_for_one},
        {Bandit, plug: Server, scheme: :http, port: port}
      ],
      strategy: :one_for_one
    )
  end

  def start_template_server(base_url) do
    DynamicSupervisor.start_child(
      Webserver.TemplateServerSupervisor,
      {TemplateServer, base_url}
    )
  end
end
