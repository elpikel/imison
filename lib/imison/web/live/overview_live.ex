defmodule Imison.Web.OverviewLive do
  @moduledoc """
  The overview at `<path>/` (`docs/design/overview.html`), the dashboard's
  landing page, with a card per full page.

  The errors card shows the unresolved count, the number of errors first
  seen in the last 24 hours whatever their status now, and the 5 most
  recently seen unresolved errors with their heat strips, and links to the
  error list. It stays current like the list does (`Imison.Web.LiveUpdates`).

  The analytics card shows the last 7 days' visitors, pageviews and bounce
  rate, a chart of visitors per day and the top 3 pages, read when the page
  opens, and links to the Analytics tab. With `analytics: false` it says how
  to turn analytics on.
  """

  use Phoenix.LiveView

  alias Imison.Analytics
  alias Imison.Errors
  alias Imison.Web.Components
  alias Imison.Web.Format
  alias Imison.Web.Layouts
  alias Imison.Web.LiveUpdates
  alias Imison.Web.Paths

  @glimpsed_errors_limit 5
  @new_errors_window_hours 24
  @analytics_range :last_7_days
  @glimpsed_pages_limit 3

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    conf = Imison.config(imison_name)

    {:ok,
     socket
     |> assign(
       conf: conf,
       dashboard_path: dashboard_path,
       page_title: "Overview",
       analytics_summary: analytics_summary(conf)
     )
     |> load_errors()
     |> LiveUpdates.attach(conf, &load_errors/1)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns = assign(assigns, analytics_range: @analytics_range)

    ~H"""
    <Layouts.app dashboard_path={@dashboard_path} current={:overview} flash={@flash} live={@live}>
      <div class="page__head">
        <div>
          <h1 class="page__title">Overview</h1>
          <p class="page__lede">A glimpse of your app’s errors and visitors. Each card opens its full page.</p>
        </div>
      </div>
      <section class="panel" id="overview-errors">
        <div class="panel__head">
          <h2 class="section-title">Errors</h2>
          <.link class="btn btn--sm" navigate={Paths.errors(@dashboard_path)}>All errors</.link>
        </div>
        <dl class="stats stats--2">
          <Components.stat_tile
            id="stat-unresolved"
            label="Unresolved"
            value={Format.with_thousands_separators(@unresolved_count)}
          />
          <Components.stat_tile
            id="stat-new-errors"
            label="New in the last 24 hours"
            value={Format.with_thousands_separators(@new_errors_count)}
          />
        </dl>
        <Components.errors_head :if={@errors != []} />
        <ul :if={@errors != []} class="errors">
          <Components.error_row
            :for={error <- @errors}
            error={error}
            hourly_counts={Map.fetch!(@hourly_counts, error.id)}
            now={@now}
            dashboard_path={@dashboard_path}
          />
        </ul>
        <div :if={@errors == []} class="empty empty--glimpse">
          <h3 class="empty__title">No unresolved errors</h3>
          <p class="empty__text">New errors appear here as they happen.</p>
        </div>
      </section>
      <section class="panel" id="overview-analytics">
        <div class="panel__head">
          <h2 class="section-title">Analytics <span :if={@analytics_summary} class="faint">· Last 7 days</span></h2>
          <.link class="btn btn--sm" navigate={Paths.analytics(@dashboard_path)}>Full analytics</.link>
        </div>
        <Components.analytics_off :if={is_nil(@analytics_summary)} />
        <.analytics_glimpse :if={@analytics_summary} summary={@analytics_summary} range={@analytics_range} />
      </section>
    </Layouts.app>
    """
  end

  attr :summary, :map, required: true
  attr :range, :atom, required: true

  defp analytics_glimpse(assigns) do
    assigns = assign(assigns, top_pages: Enum.take(assigns.summary.top_pages, @glimpsed_pages_limit))

    ~H"""
    <dl class="stats stats--3">
      <Components.visitor_stat_tiles summary={@summary} />
    </dl>
    <Components.visitors_chart :if={@summary.pageviews > 0} series={@summary.series} range={@range} />
    <Components.top_list
      :if={@summary.pageviews > 0}
      id="top-pages"
      class="toplist--glimpse"
      heading="Top pages"
      entries={@top_pages}
      name={& &1.path}
    />
    <div :if={@summary.pageviews == 0} class="empty empty--glimpse">
      <h3 class="empty__title">No pageviews in the last 7 days</h3>
      <p class="empty__text">Pages appear here as people visit your app.</p>
    </div>
    """
  end

  defp load_errors(%{assigns: %{conf: conf}} = socket) do
    now = DateTime.utc_now()
    errors = Errors.list(conf, status: :unresolved, limit: @glimpsed_errors_limit)

    assign(socket,
      errors: errors,
      hourly_counts: Errors.hourly_counts(conf, Enum.map(errors, & &1.id), now),
      unresolved_count: conf |> Errors.count_by_status([]) |> Map.fetch!(:unresolved),
      new_errors_count: Errors.count_first_seen_since(conf, DateTime.shift(now, hour: -@new_errors_window_hours)),
      now: now
    )
  end

  defp analytics_summary(%{analytics: true} = conf), do: Analytics.summary(conf, @analytics_range, DateTime.utc_now())
  defp analytics_summary(_conf), do: nil
end
