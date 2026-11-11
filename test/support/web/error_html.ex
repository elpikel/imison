defmodule Imison.Test.ErrorHTML do
  @moduledoc """
  Error pages of the test endpoint: the status message, as a host app's error view renders by default.
  """

  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
