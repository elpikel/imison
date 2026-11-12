defmodule Imison.Install do
  @moduledoc false

  @dashboard_path "/errors"
  @igniter_dependency ~s|{:igniter, "~> 0.8", only: [:dev]}|

  @spec dashboard_path() :: String.t()
  def dashboard_path, do: @dashboard_path

  @spec igniter_dependency() :: String.t()
  def igniter_dependency, do: @igniter_dependency
end
