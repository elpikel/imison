defmodule Imison.Web.LiveUpdates do
  @moduledoc """
  Keeps the errors on a connected dashboard page current, for the error list
  and the overview alike.

  With the instance's `pubsub` set, the connected page subscribes to the
  errors it records and changes, and reloads them at most once a second.
  Broadcasts only reach pages on nodes that share the PubSub, so without
  `pubsub`, or while this node has no connected nodes, the page also reloads
  from the database every few seconds. `live` says which of the two keeps the
  page current (`:broadcasts` or `:polling`, `nil` before it connects), for
  the Live indicator of `Imison.Web.Layouts.app/1`.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Imison.Config
  alias Imison.Errors.Broadcast
  alias Phoenix.LiveView.Socket

  @reload_interval_ms 1_000
  @refresh_interval_ms 5_000
  @reloading_events [:recorded, :changed]

  @doc """
  Starts keeping a connected page current: `reload` is called with the
  socket whenever its errors may have changed and returns the reloaded socket.
  """
  @spec attach(Socket.t(), Config.t(), (Socket.t() -> Socket.t())) :: Socket.t()
  def attach(socket, %Config{} = conf, reload) do
    if connected?(socket) do
      subscribed = Broadcast.subscribe(conf) == :ok
      schedule_refresh()

      socket
      |> assign(live: update_source(subscribed), live_updates: %{subscribed: subscribed, reload: :idle})
      |> attach_hook(:imison_live_updates, :handle_info, &handle_message(&1, &2, reload))
    else
      assign(socket, live: nil)
    end
  end

  defp handle_message({:imison, event, _error_ids}, socket, reload) when event in @reloading_events,
    do: {:halt, request_reload(socket, reload)}

  defp handle_message(:refresh, %{assigns: %{live_updates: %{subscribed: subscribed}}} = socket, reload) do
    schedule_refresh()

    case update_source(subscribed) do
      :polling -> {:halt, socket |> assign(live: :polling) |> request_reload(reload)}
      :broadcasts -> {:halt, assign(socket, live: :broadcasts)}
    end
  end

  defp handle_message(:reload_hold_over, %{assigns: %{live_updates: %{reload: :pending}}} = socket, reload),
    do: {:halt, reload_and_hold(socket, reload)}

  defp handle_message(:reload_hold_over, socket, _reload), do: {:halt, put_reload_state(socket, :idle)}

  defp handle_message(_message, socket, _reload), do: {:cont, socket}

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp update_source(true = _subscribed) do
    if Node.list() == [], do: :polling, else: :broadcasts
  end

  defp update_source(false = _subscribed), do: :polling

  defp request_reload(%{assigns: %{live_updates: %{reload: :idle}}} = socket, reload), do: reload_and_hold(socket, reload)

  defp request_reload(socket, _reload), do: put_reload_state(socket, :pending)

  defp reload_and_hold(socket, reload) do
    Process.send_after(self(), :reload_hold_over, @reload_interval_ms)

    socket
    |> reload.()
    |> put_reload_state(:holding)
  end

  defp put_reload_state(%{assigns: %{live_updates: live_updates}} = socket, state),
    do: assign(socket, live_updates: %{live_updates | reload: state})
end
