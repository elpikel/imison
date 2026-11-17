defmodule Imison.Analytics.Telemetry do
  @moduledoc false

  alias Imison.Analytics.Bot
  alias Imison.Analytics.ClientIP
  alias Imison.Analytics.Worker
  alias Imison.Capture.FailureLog
  alias Imison.Config

  @phoenix_request_stop [:phoenix, :router_dispatch, :stop]
  @live_view_mount_stop [:phoenix, :live_view, :mount, :stop]
  @live_view_handle_params_stop [:phoenix, :live_view, :handle_params, :stop]

  @type handler_config :: %{name: Imison.name(), remote_ip_header: String.t() | nil}

  @spec attach(Config.t()) :: :ok | {:error, :already_exists}
  def attach(%Config{name: name, remote_ip_header: remote_ip_header}) do
    :telemetry.attach_many(
      handler_id(name),
      [@phoenix_request_stop, @live_view_mount_stop, @live_view_handle_params_stop],
      &__MODULE__.handle_event/4,
      %{name: name, remote_ip_header: remote_ip_header}
    )
  end

  @spec detach(Imison.name()) :: :ok | {:error, :not_found}
  def detach(name), do: :telemetry.detach(handler_id(name))

  @spec handle_event(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          handler_config()
        ) :: :ok
  def handle_event(@phoenix_request_stop, _measurements, %{conn: conn} = metadata, %{name: name} = handler_config) do
    if innermost_dispatch?(metadata) and page_load?(conn, metadata) do
      Worker.capture(name, captured_pageview(conn, handler_config))
    end

    :ok
  catch
    kind, reason ->
      FailureLog.error("Imison failed to capture a pageview", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  def handle_event(@live_view_mount_stop, _measurements, %{socket: socket, uri: uri}, handler_config)
      when is_binary(uri) do
    see_live_page(socket, uri, handler_config)
    :ok
  catch
    kind, reason ->
      FailureLog.error("Imison failed to capture a pageview", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  def handle_event(
        @live_view_handle_params_stop,
        _measurements,
        %{socket: socket, uri: uri},
        %{name: name} = handler_config
      )
      when is_binary(uri) do
    case Process.get(live_page_key(name)) do
      nil -> see_live_page(socket, uri, handler_config)
      live_page -> follow_patch(live_page, socket, uri, name)
    end

    :ok
  catch
    kind, reason ->
      FailureLog.error("Imison failed to capture a pageview", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  def handle_event(_event, _measurements, _metadata, _handler_config), do: :ok

  defp handler_id(name), do: {__MODULE__, name}

  defp innermost_dispatch?(%{plug: plug}), do: not router?(plug)

  defp router?(module), do: Code.ensure_loaded?(module) and function_exported?(module, :__routes__, 0)

  defp page_load?(conn, metadata) do
    conn.method == "GET" and conn.status == 200 and html_response?(conn) and not dashboard_route?(metadata) and
      not Bot.bot?(user_agent(conn))
  end

  defp html_response?(conn) do
    conn
    |> Plug.Conn.get_resp_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, "text/html"))
  end

  defp dashboard_route?(metadata) do
    metadata
    |> route_modules()
    |> Enum.any?(&dashboard_module?/1)
  end

  defp route_modules(%{plug: plug, phoenix_live_view: {live_view, _action, _opts, _live_session}}), do: [plug, live_view]
  defp route_modules(%{plug: plug}), do: [plug]

  defp dashboard_module?(module) when is_atom(module),
    do: String.starts_with?(Atom.to_string(module), "Elixir.Imison.Web.")

  defp captured_pageview(conn, %{remote_ip_header: remote_ip_header}) do
    %{
      path: conn.request_path,
      referrer: conn |> Plug.Conn.get_req_header("referer") |> List.first(),
      host: conn.host,
      ip: ClientIP.address(%{headers: conn.req_headers, peer_address: conn.remote_ip}, remote_ip_header),
      user_agent: user_agent(conn),
      occurred_at: DateTime.utc_now()
    }
  end

  defp user_agent(conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> List.first()
  end

  defp live_page_key(name), do: {__MODULE__, name}

  defp see_live_page(socket, uri, %{name: name} = handler_config) do
    if tracked_live_view?(socket) and not redirected?(socket) do
      live_page = %{path: path_of(uri), visitor: live_visitor(socket, handler_config)}
      Process.put(live_page_key(name), live_page)
      if navigation_join?(socket), do: capture_live_pageview(name, live_page)
    end
  end

  defp follow_patch(%{path: last_path} = live_page, socket, uri, name) do
    path = path_of(uri)

    if path != last_path and not redirected?(socket) do
      patched_page = %{live_page | path: path}
      Process.put(live_page_key(name), patched_page)
      capture_live_pageview(name, patched_page)
    end
  end

  defp redirected?(socket), do: socket.redirected != nil

  defp tracked_live_view?(socket), do: Phoenix.LiveView.connected?(socket) and not dashboard_module?(socket.view)

  defp navigation_join?(socket) do
    match?(
      %{"_live_referer" => referer, "_mounts" => 0} when is_binary(referer),
      Phoenix.LiveView.get_connect_params(socket)
    )
  end

  defp path_of(uri), do: URI.parse(uri).path

  defp live_visitor(socket, %{remote_ip_header: remote_ip_header}) do
    user_agent = Phoenix.LiveView.get_connect_info(socket, :user_agent)

    with false <- Bot.bot?(user_agent),
         %{address: peer_address} <- Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      forwarded_headers = Phoenix.LiveView.get_connect_info(socket, :x_headers) || []

      %{
        host: socket.host_uri.host,
        ip: ClientIP.address(%{headers: forwarded_headers, peer_address: peer_address}, remote_ip_header),
        user_agent: user_agent
      }
    else
      _bot_or_unknown_visitor -> nil
    end
  end

  defp capture_live_pageview(_name, %{visitor: nil}), do: :ok

  defp capture_live_pageview(name, %{path: path, visitor: visitor}) do
    Worker.capture(name, %{
      path: path,
      referrer: nil,
      host: visitor.host,
      ip: visitor.ip,
      user_agent: visitor.user_agent,
      occurred_at: DateTime.utc_now()
    })
  end
end
