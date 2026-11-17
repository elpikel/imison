defmodule Imison.Analytics.Source do
  @moduledoc false

  @spec from_referrer(String.t() | nil, String.t()) :: String.t() | nil
  def from_referrer(referrer, request_host) when is_binary(referrer) do
    with {:ok, %URI{host: referrer_host}} when is_binary(referrer_host) and referrer_host != "" <- URI.new(referrer),
         source when source != "" <- bare_host(referrer_host),
         false <- source == bare_host(request_host) do
      source
    else
      _not_a_source -> nil
    end
  end

  def from_referrer(nil, _request_host), do: nil

  defp bare_host(host) do
    host
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end
end
