defmodule Imison.Web.AnalyticsLive do
  @moduledoc """
  The Analytics tab (`docs/design/analytics.html`): visitors, pageviews,
  bounce rate and visit duration as stat tiles, a bar chart of visitors per
  UTC hour (today) or per UTC day, and the top pages and top sources by
  visitors, for the range in the URL (`?range=today|7d|30d`, 7 days for a
  missing or unknown one).

  The numbers are read when the page opens and when the range changes; they
  don't update live. A range without pageviews shows zeros and an empty
  state instead of the chart and the lists. With `analytics: false` the tab
  says how to turn analytics on.
  """

  use Phoenix.LiveView

  alias Imison.Analytics
  alias Imison.Web.Components
  alias Imison.Web.Format
  alias Imison.Web.Layouts
  alias Imison.Web.Paths

  @ranges [
    %{range: :today, param: "today", label: "Today"},
    %{range: :last_7_days, param: "7d", label: "7 days"},
    %{range: :last_30_days, param: "30d", label: "30 days"}
  ]
  @default_range :last_7_days
  @direct_source_label "Direct / None"

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    {:ok, assign(socket, conf: Imison.config(imison_name), dashboard_path: dashboard_path, page_title: "Analytics")}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, %{assigns: %{conf: conf}} = socket) do
    range = range_from_param(params["range"])
    summary = if conf.analytics, do: Analytics.summary(conf, range, DateTime.utc_now())

    {:noreply, assign(socket, range: range, summary: summary)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns = assign(assigns, ranges: @ranges)

    ~H"""
    <Layouts.app dashboard_path={@dashboard_path} current={:analytics} flash={@flash}>
      <div class="page__head">
        <div>
          <h1 class="page__title">Analytics</h1>
          <p class="page__lede">Pageviews counted by your app’s server, without cookies. Times are in UTC.</p>
        </div>
        <nav :if={@summary} class="range" aria-label="Range">
          <.link
            :for={range <- @ranges}
            class="range__item"
            patch={range_path(@dashboard_path, range.param)}
            aria-current={if range.range == @range, do: "true"}
          >
            {range.label}
          </.link>
        </nav>
      </div>
      <section :if={is_nil(@summary)} class="panel">
        <Components.analytics_off />
      </section>
      <.metrics :if={@summary} summary={@summary} range={@range} />
    </Layouts.app>
    """
  end

  attr :summary, :map, required: true
  attr :range, :atom, required: true

  defp metrics(assigns) do
    ~H"""
    <section class="panel">
      <dl class="stats">
        <Components.visitor_stat_tiles summary={@summary} />
        <Components.stat_tile
          id="stat-visit-duration"
          label="Visit duration"
          value={Format.duration(@summary.visit_duration)}
        />
      </dl>
      <Components.visitors_chart :if={@summary.pageviews > 0} series={@summary.series} range={@range} />
    </section>
    <div :if={@summary.pageviews > 0} class="toplists">
      <.top_list_panel
        id="top-pages"
        title="Top pages"
        heading="Page"
        entries={@summary.top_pages}
        name={&page_name/1}
      />
      <.top_list_panel
        id="top-sources"
        title="Top sources"
        heading="Source"
        entries={@summary.top_sources}
        name={&source_name/1}
      />
    </div>
    <section :if={@summary.pageviews == 0} class="panel">
      <div class="empty">
        <h2 class="empty__title">No pageviews in this range</h2>
        <p class="empty__text">Pages appear here as people visit your app. Try a longer range.</p>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :heading, :string, required: true
  attr :entries, :list, required: true
  attr :name, :any, required: true

  defp top_list_panel(assigns) do
    ~H"""
    <section class="panel">
      <div class="panel__head"><h2 class="section-title">{@title}</h2></div>
      <Components.top_list id={@id} heading={@heading} entries={@entries} name={@name} />
    </section>
    """
  end

  defp range_from_param(param) do
    case Enum.find(@ranges, &(&1.param == param)) do
      %{range: range} -> range
      nil -> @default_range
    end
  end

  defp range_path(dashboard_path, param), do: "#{Paths.analytics(dashboard_path)}?#{URI.encode_query(range: param)}"

  defp page_name(%{path: path}), do: path

  defp source_name(%{source: nil}), do: @direct_source_label
  defp source_name(%{source: source}), do: source
end
