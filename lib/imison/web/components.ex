defmodule Imison.Web.Components do
  @moduledoc """
  Function components shared by the dashboard's pages, with the markup of
  `docs/design/`: the header of a list of error rows, an error's row with its
  heat strip, stat tiles, the visitors, pageviews and bounce rate tiles, the
  visitors chart, a top list and the note shown while analytics is off.
  """

  use Phoenix.Component

  alias Imison.Errors.Error
  alias Imison.Web.Format
  alias Imison.Web.Paths
  alias Phoenix.LiveView.Rendered

  @config_example "config :my_app, Imison,\n  analytics: true"

  @chart_headroom_percent 5
  @label_steps %{today: 6, last_7_days: 1, last_30_days: 5}

  @doc """
  The header over a list of error rows, naming their columns. The
  `selection` slot goes before the names; a header without one drops that
  column, like the rows under it.
  """
  slot :selection

  @spec errors_head(map()) :: Rendered.t()
  def errors_head(assigns) do
    ~H"""
    <div class={["errors__head", @selection == [] && "errors__head--glimpse"]}>
      {render_slot(@selection)}
      <span>Error</span><span>Last 24 hours</span><span style="text-align:right">Events</span><span style="text-align:right">Last seen</span>
    </div>
    """
  end

  @doc """
  An error's row: its kind linking to its detail page, the Back again and
  Muted flags, its message and location, the heat strip of its `hourly_counts`
  for the last 24 hours, its occurrence count and how long before `now` it was
  last seen. The `selection` slot goes before it all; a row without one drops
  that column.
  """
  attr :error, :map, required: true, doc: "an error, with its id, kind, message, status and counts"
  attr :hourly_counts, :list, required: true
  attr :now, DateTime, required: true
  attr :dashboard_path, :string, required: true
  slot :selection

  @spec error_row(map()) :: Rendered.t()
  def error_row(assigns) do
    ~H"""
    <li id={"error-#{@error.id}"} class={["error-row", @selection == [] && "error-row--glimpse"]}>
      {render_slot(@selection)}
      <div class="error-row__main">
        <div class="error-row__title">
          <.link class="error-row__kind truncate" navigate={Paths.error(@dashboard_path, @error.id)}>{@error.kind}</.link>
          <span :if={back_again?(@error)} class="flag flag--regressed">Back again</span>
          <span :if={@error.muted} class="flag flag--off">Muted</span>
        </div>
        <p class="error-row__message truncate">{@error.message}</p>
        <div :if={@error.location} class="error-row__meta">
          <span class="error-row__loc">{@error.location}</span>
        </div>
      </div>
      <.heat_strip counts={@hourly_counts} />
      <span class="error-row__events">{Format.with_thousands_separators(@error.occurrence_count)}</span>
      <span class="error-row__seen">{time_ago(DateTime.diff(@now, @error.last_seen_at))}</span>
    </li>
    """
  end

  @doc """
  A stat tile: a label over its value.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  @spec stat_tile(map()) :: Rendered.t()
  def stat_tile(assigns) do
    ~H"""
    <div class="stat" id={@id}>
      <dt class="stat__label">{@label}</dt>
      <dd class="stat__value">{@value}</dd>
    </div>
    """
  end

  @doc """
  The stat tiles of an analytics summary's visitors, pageviews and bounce
  rate, to place in a `stats` list next to any other tiles.
  """
  attr :summary, :map, required: true

  @spec visitor_stat_tiles(map()) :: Rendered.t()
  def visitor_stat_tiles(assigns) do
    ~H"""
    <.stat_tile id="stat-visitors" label="Visitors" value={Format.with_thousands_separators(@summary.visitors)} />
    <.stat_tile id="stat-pageviews" label="Pageviews" value={Format.with_thousands_separators(@summary.pageviews)} />
    <.stat_tile id="stat-bounce-rate" label="Bounce rate" value={Format.percentage(@summary.bounce_rate)} />
    """
  end

  @doc """
  A bar chart of the visitors in each point of `series`: per UTC hour for
  `:today`, per UTC day for the other ranges, captioned with its UTC bucket,
  with a label under every bar of the last 7 days, every fifth day of the
  last 30 and every sixth hour. A bucket with any visitors always shows a
  visible bar, however small next to the peak; an empty bucket shows none.
  Hovering a bar's column shows a tooltip with its hour or day and visitors,
  kept inside the plot; a visually hidden table gives screen readers the same
  numbers.
  """
  attr :series, :list, required: true
  attr :range, :atom, values: [:today, :last_7_days, :last_30_days], required: true

  @spec visitors_chart(map()) :: Rendered.t()
  def visitors_chart(%{series: series, range: range} = assigns) do
    peak = series |> Enum.map(& &1.visitors) |> Enum.max(fn -> 0 end)
    caption = "Visitors per #{bucket(range)} (UTC)"

    assigns =
      assign(assigns,
        peak: peak,
        caption: caption,
        bars: chart_bars(series, range, peak)
      )

    ~H"""
    <figure class="chart" style={"--buckets:#{length(@bars)}"}>
      <figcaption class="chart__caption">
        <span class="section-title">{@caption}</span><span class="faint">Peak {Format.with_thousands_separators(@peak)}</span>
      </figcaption>
      <div class="chart__plot" role="img" aria-label={"#{@caption}, peak #{Format.with_thousands_separators(@peak)}"}>
        <div :for={bar <- @bars} class="chart__slot" style={"--position:#{bar.position}%"}>
          <span class={["chart__bar", bar.visitors == 0 && "chart__bar--empty"]} style={"--height:#{bar.height}%"}></span>
          <span class="chart__tip">{bar.tooltip}</span>
        </div>
      </div>
      <div class="chart__labels" aria-hidden="true">
        <span :for={bar <- @bars}>{bar.label}</span>
      </div>
      <table class="visually-hidden">
        <caption>{@caption}</caption>
        <tr :for={bar <- @bars}>
          <th scope="row">{bar.name}</th>
          <td>{bar.visitors}</td>
        </tr>
      </table>
    </figure>
    """
  end

  @doc """
  A table of `entries` (each with `visitors` and `pageviews`) named by
  `name`, each row's soft bar showing its share of the top visitor count.
  """
  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :entries, :list, required: true
  attr :name, :any, required: true, doc: "a function giving an entry's name"
  attr :class, :string, default: nil

  @spec top_list(map()) :: Rendered.t()
  def top_list(%{entries: entries} = assigns) do
    top_visitors = entries |> Enum.map(& &1.visitors) |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, top_visitors: top_visitors)

    ~H"""
    <table class={["toplist", @class]} id={@id}>
      <thead>
        <tr>
          <th scope="col">{@heading}</th>
          <th scope="col">Visitors</th>
          <th scope="col">Pageviews</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={entry <- @entries}>
          <td>
            <span class="toplist__bar" style={"--share:#{round(entry.visitors * 100 / @top_visitors)}%"}></span><span class="toplist__name">{@name.(entry)}</span>
          </td>
          <td>{Format.with_thousands_separators(entry.visitors)}</td>
          <td>{Format.with_thousands_separators(entry.pageviews)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  The note shown while `analytics: false`: analytics is off, and the option
  that turns it on.
  """
  @spec analytics_off(map()) :: Rendered.t()
  def analytics_off(assigns) do
    assigns = assign(assigns, config_example: @config_example)

    ~H"""
    <div class="empty">
      <h2 class="empty__title">Analytics is off</h2>
      <p class="empty__text">
        Turn it on in Imison’s options and restart your app. Imison then counts pageviews on your app’s HTML pages and LiveView navigations.
      </p>
      <pre class="codeblock analytics-off__code">{@config_example}</pre>
    </div>
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

  defp back_again?(%Error{regressed_at: nil}), do: false
  defp back_again?(%Error{status: status}), do: status == :unresolved

  defp heat_level(0, _busiest), do: nil
  defp heat_level(count, busiest), do: div(count * 4 + busiest - 1, busiest)

  defp events_in_last_24_hours(1), do: "1 event in the last 24 hours"
  defp events_in_last_24_hours(total), do: "#{Format.with_thousands_separators(total)} events in the last 24 hours"

  defp time_ago(seconds) when seconds < 60, do: "just now"
  defp time_ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min ago"
  defp time_ago(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)} h ago"
  defp time_ago(seconds), do: "#{div(seconds, 86_400)} d ago"

  defp bucket(:today), do: :hour
  defp bucket(_range), do: :day

  defp chart_bars(series, range, peak) do
    bucket = bucket(range)
    label_step = Map.fetch!(@label_steps, range)
    last_index = max(length(series) - 1, 1)

    series
    |> Enum.with_index()
    |> Enum.map(fn {%{starts_at: starts_at, visitors: visitors}, index} ->
      name = bucket_name(starts_at, bucket)

      %{
        name: name,
        tooltip: "#{name} · #{visitors_label(visitors)}",
        label: if(rem(index, label_step) == 0, do: bucket_label(starts_at, bucket)),
        visitors: visitors,
        position: rounded(index * 100 / last_index),
        height: rounded(bar_height(visitors, peak))
      }
    end)
  end

  defp bar_height(_visitors, 0), do: 0
  defp bar_height(visitors, peak), do: visitors * (100 - @chart_headroom_percent) / peak

  defp rounded(number), do: :erlang.float_to_binary(number / 1, decimals: 1)

  defp bucket_name(starts_at, :hour),
    do:
      "#{Calendar.strftime(starts_at, "%H:00")}–#{starts_at |> DateTime.shift(hour: 1) |> Calendar.strftime("%H:00")} UTC"

  defp bucket_name(starts_at, :day), do: Calendar.strftime(starts_at, "%-d %b")

  defp bucket_label(starts_at, :hour), do: Calendar.strftime(starts_at, "%H:00")
  defp bucket_label(starts_at, :day), do: bucket_name(starts_at, :day)

  defp visitors_label(1), do: "1 visitor"
  defp visitors_label(visitors), do: "#{Format.with_thousands_separators(visitors)} visitors"
end
