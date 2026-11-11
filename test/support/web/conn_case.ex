defmodule Imison.ConnCase do
  @moduledoc """
  Test case for requests to the dashboard through `Imison.Test.Endpoint`, with
  `Phoenix.ConnTest` and `Phoenix.LiveViewTest` imported, `browser_conn/0`,
  `next_browser_conn/1`, `login_form_token/1` and `sign_in/3`.

  Each test checks out its own sandbox connection, shared with the processes
  it starts (such as a LiveView) unless the test is `async: true`.
  """

  use ExUnit.CaseTemplate

  import Phoenix.ConnTest

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint Imison.Test.Endpoint

  using do
    quote do
      import Imison.ConnCase
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn

      @endpoint Imison.Test.Endpoint
    end
  end

  setup tags do
    owner = Sandbox.start_owner!(Imison.Test.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  @doc """
  A conn as a browser sends it: unlike `Phoenix.ConnTest.build_conn/0`, it
  keeps the `:browser` pipeline's CSRF protection on, including Plug's check
  against cross-origin requests for JavaScript.
  """
  @spec browser_conn() :: Plug.Conn.t()
  def browser_conn do
    Plug.Conn.put_private(build_conn(), :plug_skip_csrf_protection, false)
  end

  @doc """
  The next request of the browser that sent `conn`: it carries the cookies
  `conn` received, with CSRF protection on.
  """
  @spec next_browser_conn(Plug.Conn.t()) :: Plug.Conn.t()
  def next_browser_conn(conn) do
    conn
    |> recycle()
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
  end

  @doc """
  The CSRF token in the sign-in form of a rendered login page.
  """
  @spec login_form_token(String.t()) :: String.t()
  def login_form_token(login_page) do
    [token] =
      login_page
      |> LazyHTML.from_document()
      |> LazyHTML.query("form input[name=_csrf_token]")
      |> LazyHTML.attribute("value")

    token
  end

  @doc """
  Signs in to the dashboard at `dashboard_path` as a browser does, and returns
  the conn for that browser's next request.
  """
  @spec sign_in(String.t(), String.t(), String.t()) :: Plug.Conn.t()
  def sign_in(dashboard_path, username, password) do
    login_conn = get(browser_conn(), dashboard_path <> "/login")
    token = login_conn |> html_response(200) |> login_form_token()

    login_conn
    |> next_browser_conn()
    |> post(dashboard_path <> "/login", %{"_csrf_token" => token, "username" => username, "password" => password})
    |> next_browser_conn()
  end
end
