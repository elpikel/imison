defmodule Imison.Test.Endpoint do
  @moduledoc """
  A host endpoint for dashboard tests: a cookie session and the LiveView socket at `/live`, as a host app has.
  """

  use Phoenix.Endpoint, otp_app: :imison

  @session_options [store: :cookie, key: "_imison_test_key", signing_salt: "imison-test-session"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug(Plug.Session, @session_options)
  plug(Imison.Test.Router)
end
