defmodule Imison.Test.PageController do
  @moduledoc """
  Pages of the test host app: an HTML page, a JSON response and a redirect, as a host app serves them.
  """

  use Phoenix.Controller, formats: [:html, :json]

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params), do: html(conn, "<!DOCTYPE html><html><body><h1>Pricing</h1></body></html>")

  @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, _params), do: json(conn, %{status: "ok"})

  @spec moved(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def moved(conn, _params), do: redirect(conn, to: "/pricing")
end
