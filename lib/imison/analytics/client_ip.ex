defmodule Imison.Analytics.ClientIP do
  @moduledoc false

  @type request :: %{headers: [{String.t(), String.t()}], peer_address: :inet.ip_address()}

  @spec address(request(), String.t() | nil) :: String.t()
  def address(%{peer_address: peer_address}, nil), do: format(peer_address)

  def address(%{headers: headers, peer_address: peer_address}, remote_ip_header) do
    case forwarded_address(headers, String.downcase(remote_ip_header)) do
      {:ok, forwarded_address} -> format(forwarded_address)
      :error -> format(peer_address)
    end
  end

  defp forwarded_address(headers, header_name) do
    with {_name, value} <- List.keyfind(headers, header_name, 0),
         [first_address | _proxies] <- String.split(value, ","),
         {:ok, address} <-
           first_address |> String.trim() |> without_port() |> String.to_charlist() |> :inet.parse_strict_address() do
      {:ok, address}
    else
      _missing_or_unparsable -> :error
    end
  end

  defp without_port("[" <> bracketed_address), do: bracketed_address |> String.split("]", parts: 2) |> List.first()

  defp without_port(address) do
    case String.split(address, ":") do
      [ipv4_address, _port] -> ipv4_address
      _bare_or_ipv6_address -> address
    end
  end

  defp format(address) do
    address
    |> :inet.ntoa()
    |> to_string()
  end
end
