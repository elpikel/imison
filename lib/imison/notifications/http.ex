defmodule Imison.Notifications.HTTP do
  @moduledoc false

  @connect_timeout_ms 5_000
  @answer_timeout_ms 5_000

  @type failure :: {:http_status, non_neg_integer()} | atom() | {atom(), atom()}

  @spec post_json(String.t(), iodata(), [{String.t(), String.t()}]) :: :ok | {:error, failure()}
  def post_json(url, body, headers) when is_binary(url) do
    request =
      {String.to_charlist(url), Enum.map(headers, &charlist_header/1), ~c"application/json", IO.iodata_to_binary(body)}

    :post
    |> :httpc.request(request, http_options(url), body_format: :binary)
    |> outcome()
  catch
    _kind, _reason -> {:error, :request_failed}
  end

  defp http_options(url) do
    url
    |> URI.parse()
    |> tls_options()
    |> Enum.concat(timeout: @answer_timeout_ms, connect_timeout: @connect_timeout_ms, autoredirect: false)
  end

  defp tls_options(%URI{scheme: "https"}) do
    [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp tls_options(%URI{}), do: []

  defp charlist_header({name, value}), do: {String.to_charlist(name), String.to_charlist(value)}

  defp outcome({:ok, {{_version, status, _reason_phrase}, _headers, _body}}) when status in 200..299, do: :ok
  defp outcome({:ok, {{_version, status, _reason_phrase}, _headers, _body}}), do: {:error, {:http_status, status}}
  defp outcome({:error, reason}), do: {:error, failure(reason)}

  defp failure({:failed_connect, details}) when is_list(details), do: {:failed_connect, connect_failure(details)}
  defp failure(:timeout), do: :timeout
  defp failure(:socket_closed_remotely), do: :socket_closed_remotely
  defp failure(_reason), do: :request_failed

  defp connect_failure(details) do
    Enum.find_value(details, :unknown, fn
      {:inet, _families, {:tls_alert, {alert, _description}}} when is_atom(alert) -> alert
      {:inet, _families, reason} when is_atom(reason) -> reason
      _detail -> nil
    end)
  end
end
