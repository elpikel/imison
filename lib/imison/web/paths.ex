defmodule Imison.Web.Paths do
  @moduledoc """
  URL paths of the routes of a dashboard mounted at `dashboard_path` with
  `Imison.Web.Router.imison_dashboard/2`: login, logout and an error's detail
  page.
  """

  @spec login(String.t()) :: String.t()
  def login(dashboard_path), do: Path.join(dashboard_path, "login")

  @spec logout(String.t()) :: String.t()
  def logout(dashboard_path), do: Path.join(dashboard_path, "logout")

  @spec error(String.t(), integer()) :: String.t()
  def error(dashboard_path, error_id), do: Path.join([dashboard_path, "errors", Integer.to_string(error_id)])
end
