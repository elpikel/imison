defmodule Imison.Install do
  @moduledoc false

  @dashboard_path "/imison"
  @igniter_dependency ~s|{:igniter, "~> 0.8", only: [:dev]}|
  @live_socket_path "/live"
  @visitor_details [:peer_data, :user_agent, :x_headers]

  @spec dashboard_path() :: String.t()
  def dashboard_path, do: @dashboard_path

  @spec igniter_dependency() :: String.t()
  def igniter_dependency, do: @igniter_dependency

  @spec live_socket_path() :: String.t()
  def live_socket_path, do: @live_socket_path

  @spec visitor_details() :: [atom()]
  def visitor_details, do: @visitor_details
end
