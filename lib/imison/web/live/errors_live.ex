defmodule Imison.Web.ErrorsLive do
  @moduledoc """
  The error list at `<path>/errors` (`docs/design/errors.html`): one
  tab per status with its count, a search over kind, message and location,
  and the most recently seen errors first. The status and the search live in
  the URL (`?status=resolved&q=timeout`).

  With the instance's `pubsub` set, the connected list subscribes to the
  errors it records and reloads the page and counts at most once a second,
  showing the design's Live indicator. Status changes and mutes made
  elsewhere reload it the same way. Broadcasts only reach lists on nodes that
  share the PubSub, so without `pubsub`, or while this node has no connected
  nodes, the connected list also refreshes from the database every few
  seconds, and the indicator says so.

  Rows can be selected, one by one or all at once; while some are, the bulk
  bar offers the status changes that move them off the current tab. The
  selection lives on the server and holds only listed errors: changing tab or
  search, or acting on it, clears it.
  """

  use Phoenix.LiveView

  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Web.Components
  alias Imison.Web.Format
  alias Imison.Web.Layouts
  alias Imison.Web.LiveUpdates
  alias Imison.Web.Paths

  @bulk_actions %{
    unresolved: [:resolved, :ignored],
    resolved: [:unresolved, :ignored],
    ignored: [:unresolved, :resolved]
  }
  @action_labels %{resolved: "Resolve", ignored: "Ignore", unresolved: "Mark unresolved"}

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    conf = Imison.config(imison_name)

    {:ok,
     socket
     |> assign(conf: conf, dashboard_path: dashboard_path, page_title: "Errors", selected: MapSet.new())
     |> LiveUpdates.attach(conf, &load_list/1)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       status: status_from_param(params["status"]),
       search: search_from_param(params["q"]),
       selected: MapSet.new()
     )
     |> load_list()}
  end

  @impl Phoenix.LiveView
  def handle_event("search", params, %{assigns: assigns} = socket) do
    search = search_from_param(params["q"])
    {:noreply, push_patch(socket, to: list_path(assigns.dashboard_path, assigns.status, search))}
  end

  def handle_event("toggle_selection", params, %{assigns: %{errors: errors, selected: selected}} = socket) do
    case Enum.find(errors, &(Integer.to_string(&1.id) == params["id"])) do
      %Error{id: error_id} -> {:noreply, assign(socket, selected: toggle(selected, error_id))}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("toggle_all", _params, %{assigns: %{errors: errors, selected: selected}} = socket) do
    if all_selected?(errors, selected) do
      {:noreply, assign(socket, selected: MapSet.new())}
    else
      {:noreply, assign(socket, selected: MapSet.new(errors, & &1.id))}
    end
  end

  def handle_event("set_status", params, %{assigns: %{conf: conf, selected: selected}} = socket) do
    case Errors.set_status(conf, MapSet.to_list(selected), params["status"]) do
      {:ok, _count} -> {:noreply, socket |> assign(selected: MapSet.new()) |> load_list()}
      {:error, :invalid_status} -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app dashboard_path={@dashboard_path} flash={@flash} live={@live}>
      <div class="page__head">
        <div>
          <h1 class="page__title">Errors</h1>
        </div>
      </div>
      <nav class="tabs" aria-label="Status">
        <.link
          :for={status <- Error.statuses()}
          class="tabs__item"
          patch={list_path(@dashboard_path, status, @search)}
          aria-current={to_string(status == @status)}
        >
          {Format.status_label(status)} <span class="tabs__count">{@counts[status]}</span>
        </.link>
      </nav>
      <section class="panel">
        <form id="error-search" class="toolbar" role="search" phx-change="search" phx-submit="search">
          <label class="toolbar__grow">
            <span class="visually-hidden">Search errors</span>
            <input
              class="input"
              type="search"
              name="q"
              value={@search}
              placeholder="Search by error, message or file"
              autocomplete="off"
              phx-debounce="300"
            />
          </label>
        </form>
        <.error_list
          :if={@errors != []}
          errors={@errors}
          selected={@selected}
          actions={bulk_actions(@status)}
          hourly_counts={@hourly_counts}
          total={@counts[@status]}
          dashboard_path={@dashboard_path}
          now={@now}
        />
        <.empty_state
          :if={@errors == []}
          status={@status}
          search={@search}
          dashboard_path={@dashboard_path}
        />
      </section>
    </Layouts.app>
    """
  end

  attr :errors, :list, required: true
  attr :selected, MapSet, required: true
  attr :actions, :list, required: true
  attr :hourly_counts, :map, required: true
  attr :total, :integer, required: true
  attr :now, DateTime, required: true
  attr :dashboard_path, :string, required: true

  defp error_list(assigns) do
    ~H"""
    <div :if={MapSet.size(@selected) > 0} class="bulkbar">
      <span>{MapSet.size(@selected)} selected</span>
      <button
        :for={status <- @actions}
        class="btn btn--sm"
        type="button"
        phx-click="set_status"
        phx-value-status={status}
      >
        {action_label(status)}
      </button>
    </div>
    <Components.errors_head>
      <:selection>
        <input
          class="checkbox"
          type="checkbox"
          aria-label="Select all"
          checked={all_selected?(@errors, @selected)}
          phx-click="toggle_all"
        />
      </:selection>
    </Components.errors_head>
    <ul class="errors">
      <Components.error_row
        :for={error <- @errors}
        error={error}
        hourly_counts={Map.fetch!(@hourly_counts, error.id)}
        now={@now}
        dashboard_path={@dashboard_path}
      >
        <:selection>
          <input
            class="checkbox error-row__check"
            type="checkbox"
            aria-label={"Select #{error.kind}"}
            checked={MapSet.member?(@selected, error.id)}
            phx-click="toggle_selection"
            phx-value-id={error.id}
          />
        </:selection>
      </Components.error_row>
    </ul>
    <p class="errors__foot">{list_summary(length(@errors), @total)}</p>
    """
  end

  attr :status, :atom, required: true
  attr :search, :string, required: true
  attr :dashboard_path, :string, required: true

  defp empty_state(%{search: search} = assigns) when search != "" do
    ~H"""
    <div class="empty">
      <h2 class="empty__title">No matching errors</h2>
      <p class="empty__text">No {String.downcase(Format.status_label(@status))} error matches “{@search}”.</p>
      <.link class="btn" patch={list_path(@dashboard_path, @status, "")}>Clear search</.link>
    </div>
    """
  end

  defp empty_state(%{status: :unresolved} = assigns) do
    ~H"""
    <div class="empty">
      <h2 class="empty__title">No unresolved errors</h2>
      <p class="empty__text">
        Nothing has failed since you last resolved everything. New errors appear here as they happen.
      </p>
      <.link class="btn" patch={list_path(@dashboard_path, :resolved, "")}>Show resolved errors</.link>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="empty">
      <h2 class="empty__title">No {String.downcase(Format.status_label(@status))} errors</h2>
      <p class="empty__text">Errors you mark as {String.downcase(Format.status_label(@status))} appear here.</p>
    </div>
    """
  end

  defp load_list(%{assigns: %{conf: conf, status: status, search: search, selected: selected}} = socket) do
    now = DateTime.utc_now()
    errors = Errors.list(conf, status: status, search: search)

    assign(socket,
      errors: errors,
      selected: MapSet.intersection(selected, MapSet.new(errors, & &1.id)),
      hourly_counts: Errors.hourly_counts(conf, Enum.map(errors, & &1.id), now),
      counts: Errors.count_by_status(conf, search: search),
      now: now
    )
  end

  defp toggle(selected, error_id) do
    if MapSet.member?(selected, error_id),
      do: MapSet.delete(selected, error_id),
      else: MapSet.put(selected, error_id)
  end

  defp all_selected?([], _selected), do: false
  defp all_selected?(errors, selected), do: Enum.all?(errors, &MapSet.member?(selected, &1.id))

  defp bulk_actions(status), do: Map.fetch!(@bulk_actions, status)

  defp action_label(status), do: Map.fetch!(@action_labels, status)

  defp status_from_param(param) do
    Enum.find(Error.statuses(), Error.default_status(), &(Atom.to_string(&1) == param))
  end

  defp search_from_param(param) when is_binary(param), do: param
  defp search_from_param(_param), do: ""

  defp list_path(dashboard_path, status, search) do
    query =
      []
      |> put_search(search)
      |> put_status(status)
      |> URI.encode_query()

    list_path = Paths.errors(dashboard_path)

    case query do
      "" -> list_path
      query -> list_path <> "?" <> query
    end
  end

  defp put_status(query, status) do
    if status == Error.default_status(), do: query, else: [{:status, status} | query]
  end

  defp put_search(query, search) do
    if String.trim(search) == "", do: query, else: [{:q, search} | query]
  end

  defp list_summary(shown, total) when shown < total, do: "The #{shown} most recently seen of #{total} errors"
  defp list_summary(1, _total), do: "1 error"
  defp list_summary(shown, _total), do: "#{shown} errors"
end
