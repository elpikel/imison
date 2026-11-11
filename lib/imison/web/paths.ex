defmodule Imison.Web.Paths do
  @moduledoc """
  URL paths of the login and logout routes of a dashboard mounted at
  `dashboard_path` with `Imison.Web.Router.imison_dashboard/2`.
  """

  @spec login(String.t()) :: String.t()
  def login(dashboard_path), do: Path.join(dashboard_path, "login")

  @spec logout(String.t()) :: String.t()
  def logout(dashboard_path), do: Path.join(dashboard_path, "logout")
end
