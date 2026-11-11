defmodule Imison.ConnCase do
  @moduledoc """
  Test case for requests to the dashboard through `Imison.Test.Endpoint`, with
  `Phoenix.ConnTest` and `Phoenix.LiveViewTest` imported, and `browser_conn/0`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Imison.ConnCase
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn

      @endpoint Imison.Test.Endpoint
    end
  end

  @doc """
  A conn as a browser sends it: unlike `Phoenix.ConnTest.build_conn/0`, it
  keeps the `:browser` pipeline's CSRF protection on, including Plug's check
  against cross-origin requests for JavaScript.
  """
  @spec browser_conn() :: Plug.Conn.t()
  def browser_conn do
    Plug.Conn.put_private(Phoenix.ConnTest.build_conn(), :plug_skip_csrf_protection, false)
  end
end
