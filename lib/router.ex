defmodule Router do
  @moduledoc """
  Router that serves static files from priv/static and forwards other requests to Server.
  Static files are served at /static/* from priv/static/ directory.
  All other requests are handled by the Server plug.
  """

  use Plug.Router

  plug(Plug.Static,
    at: "/static",
    from: {:webserver, "priv/static"},
    gzip: false
  )

  plug(:match)
  plug(:dispatch)

  forward("/", to: Server)
end
