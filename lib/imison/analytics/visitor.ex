defmodule Imison.Analytics.Visitor do
  @moduledoc false

  @spec id(%{salt: binary(), ip: String.t(), user_agent: String.t()}) :: integer()
  def id(%{salt: salt, ip: ip, user_agent: user_agent}) do
    <<visitor_id::signed-integer-size(64), _rest::binary>> = :crypto.hash(:sha256, [salt, ip, user_agent])
    visitor_id
  end
end
