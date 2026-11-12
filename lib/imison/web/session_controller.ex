defmodule Imison.Web.SessionController do
  @moduledoc """
  Signs in to the dashboard and out of it, at `<path>/login` and `<path>/logout`
  of a dashboard mounted with `Imison.Web.Router.imison_dashboard/2`.

  A plain controller rather than a LiveView, because only a plain request can
  write the host's session cookie. The route's private `:imison_name` and
  `:imison_dashboard_path`, set by the router, name the instance whose login is
  checked and the dashboard to return to.

  Repeated failed sign-ins are slowed down: while a wait is running, or when
  the failed sign-ins can't be read, a sign-in is refused before its
  credentials are checked.
  """

  use Phoenix.Controller, formats: [:html]

  alias Imison.Web.Auth
  alias Imison.Web.Layouts
  alias Imison.Web.LoginThrottle
  alias Imison.Web.Paths
  alias Imison.Web.SessionHTML

  plug(:put_root_layout, html: {Layouts, :root})
  plug(:put_view, html: SessionHTML)

  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, _params), do: render_login(conn, nil)

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(%{private: %{imison_name: imison_name, imison_dashboard_path: dashboard_path}} = conn, params) do
    config = Imison.config(imison_name)
    check_credentials = fn -> Auth.valid_credentials?(config, params["username"], params["password"]) end

    case LoginThrottle.attempt(config, DateTime.utc_now(), check_credentials) do
      :accepted ->
        conn
        |> Auth.sign_in(config)
        |> redirect(to: dashboard_path)

      :rejected ->
        conn
        |> put_status(:unauthorized)
        |> render_login("Wrong username or password.")

      {:wait, wait_seconds} ->
        conn
        |> put_status(:too_many_requests)
        |> render_login("Too many failed sign-ins. Try again in #{seconds(wait_seconds)}.")

      :unavailable ->
        conn
        |> put_status(:service_unavailable)
        |> render_login("Sign-in is unavailable. Try again shortly.")
    end
  end

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(%{private: %{imison_dashboard_path: dashboard_path}} = conn, _params) do
    conn
    |> Auth.sign_out()
    |> redirect(to: Paths.login(dashboard_path))
  end

  defp render_login(%{private: %{imison_dashboard_path: dashboard_path}} = conn, error) do
    render(conn, :new,
      dashboard_path: dashboard_path,
      login_path: Paths.login(dashboard_path),
      error: error,
      page_title: "Sign in"
    )
  end

  defp seconds(1), do: "1 second"
  defp seconds(count), do: "#{count} seconds"
end
