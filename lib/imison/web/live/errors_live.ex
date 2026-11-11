defmodule Imison.Web.ErrorsLive do
  @moduledoc """
  The error list, the dashboard's home page (`docs/design/errors.html`): one
  tab per status with its count, a search over kind, message and location,
  and the most recently seen errors first. The status and the search live in
  the URL (`?status=resolved&q=timeout`).
  """

  use Phoenix.LiveView

  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Web.Layouts

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    {:ok,
     assign(socket,
       conf: Imison.config(imison_name),
       dashboard_path: dashboard_path,
       page_title: "Errors"
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, %{assigns: %{conf: conf}} = socket) do
    status = status_from_param(params["status"])
    search = search_from_param(params["q"])
    now = DateTime.utc_now()
    errors = Errors.list(conf, status: status, search: search)

    {:noreply,
     assign(socket,
       status: status,
       search: search,
       errors: errors,
       hourly_counts: Errors.hourly_counts(conf, Enum.map(errors, & &1.id), now),
       counts: Errors.count_by_status(conf, search: search),
       now: now
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("search", params, %{assigns: assigns} = socket) do
    search = search_from_param(params["q"])
    {:noreply, push_patch(socket, to: list_path(assigns.dashboard_path, assigns.status, search))}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app dashboard_path={@dashboard_path}>
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
          {status_label(status)} <span class="tabs__count">{@counts[status]}</span>
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
          hourly_counts={@hourly_counts}
          total={@counts[@status]}
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
  attr :hourly_counts, :map, required: true
  attr :total, :integer, required: true
  attr :now, DateTime, required: true

  defp error_list(assigns) do
    ~H"""
    <div class="errors__head">
      <span></span><span>Error</span><span>Last 24 hours</span><span style="text-align:right">Events</span><span style="text-align:right">Last seen</span>
    </div>
    <ul class="errors">
      <li :for={error <- @errors} id={"error-#{error.id}"} class="error-row">
        <div class="error-row__main">
          <div class="error-row__title">
            <span class="error-row__kind truncate">{error.kind}</span>
            <span :if={back_again?(error)} class="flag flag--regressed">Back again</span>
          </div>
          <p class="error-row__message truncate">{error.message}</p>
          <div :if={error.location} class="error-row__meta">
            <span class="error-row__loc">{error.location}</span>
          </div>
        </div>
        <.heat_strip counts={Map.fetch!(@hourly_counts, error.id)} />
        <span class="error-row__events">{with_thousands_separators(error.occurrence_count)}</span>
        <span class="error-row__seen">{time_ago(DateTime.diff(@now, error.last_seen_at))}</span>
      </li>
    </ul>
    <p class="errors__foot">{list_summary(length(@errors), @total)}</p>
    """
  end

  attr :counts, :list, required: true

  defp heat_strip(%{counts: counts} = assigns) do
    assigns = assign(assigns, total: Enum.sum(counts), busiest: Enum.max(counts))

    ~H"""
    <div class="heat error-row__heat" role="img" aria-label={events_in_last_24_hours(@total)}>
      <i :for={count <- @counts} data-l={heat_level(count, @busiest)}></i>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :search, :string, required: true
  attr :dashboard_path, :string, required: true

  defp empty_state(%{search: search} = assigns) when search != "" do
    ~H"""
    <div class="empty">
      <h2 class="empty__title">No matching errors</h2>
      <p class="empty__text">No {String.downcase(status_label(@status))} error matches “{@search}”.</p>
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
      <h2 class="empty__title">No {String.downcase(status_label(@status))} errors</h2>
      <p class="empty__text">Errors you mark as {String.downcase(status_label(@status))} appear here.</p>
    </div>
    """
  end

  defp status_from_param(param) do
    Enum.find(Error.statuses(), Error.default_status(), &(Atom.to_string(&1) == param))
  end

  defp search_from_param(param) when is_binary(param), do: param
  defp search_from_param(_param), do: ""

  defp status_label(status), do: status |> Atom.to_string() |> String.capitalize()

  defp list_path(dashboard_path, status, search) do
    query =
      []
      |> put_search(search)
      |> put_status(status)
      |> URI.encode_query()

    case query do
      "" -> dashboard_path
      query -> dashboard_path <> "?" <> query
    end
  end

  defp put_status(query, status) do
    if status == Error.default_status(), do: query, else: [{:status, status} | query]
  end

  defp put_search(query, search) do
    if String.trim(search) == "", do: query, else: [{:q, search} | query]
  end

  defp back_again?(%Error{regressed_at: nil}), do: false
  defp back_again?(%Error{status: status}), do: status == :unresolved

  defp heat_level(0, _busiest), do: nil
  defp heat_level(count, busiest), do: div(count * 4 + busiest - 1, busiest)

  defp events_in_last_24_hours(1), do: "1 event in the last 24 hours"
  defp events_in_last_24_hours(total), do: "#{with_thousands_separators(total)} events in the last 24 hours"

  defp with_thousands_separators(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp time_ago(seconds) when seconds < 60, do: "just now"
  defp time_ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min ago"
  defp time_ago(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)} h ago"
  defp time_ago(seconds), do: "#{div(seconds, 86_400)} d ago"

  defp list_summary(shown, total) when shown < total, do: "The #{shown} most recently seen of #{total} errors"
  defp list_summary(1, _total), do: "1 error"
  defp list_summary(shown, _total), do: "#{shown} errors"
end
