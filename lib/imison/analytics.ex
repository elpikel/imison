defmodule Imison.Analytics do
  @moduledoc false

  import Ecto.Query

  alias Imison.Analytics.Pageview
  alias Imison.Analytics.Period
  alias Imison.Analytics.Salt
  alias Imison.Analytics.Source
  alias Imison.Analytics.Visitor
  alias Imison.BatchDelete
  alias Imison.Config

  @typedoc """
  A pageview as captured from a request, before the visitor is hashed.

  `ip` is the client address as a string (e.g. `"203.0.113.7"`); `host` is the
  request's host, used to tell a referral from an internal link.
  """
  @type captured_pageview :: %{
          path: String.t(),
          referrer: String.t() | nil,
          host: String.t(),
          ip: String.t(),
          user_agent: String.t(),
          occurred_at: DateTime.t()
        }

  @typedoc """
  The metrics for a range.

  `bounce_rate` is a whole percentage (0-100) of visits with a single pageview;
  `visit_duration` is the average first-to-last pageview time per visit, in whole
  seconds. A top source of `nil` stands for pageviews without a source
  ("Direct / None"). `series` holds one visitor count per UTC hour for `:today`
  and per UTC day otherwise, oldest first, zero where there was no traffic.
  """
  @type summary :: %{
          visitors: non_neg_integer(),
          pageviews: non_neg_integer(),
          visits: non_neg_integer(),
          bounce_rate: 0..100,
          visit_duration: non_neg_integer(),
          top_pages: [%{path: String.t(), visitors: pos_integer(), pageviews: pos_integer()}],
          top_sources: [%{source: String.t() | nil, visitors: pos_integer(), pageviews: pos_integer()}],
          series: [%{starts_at: DateTime.t(), visitors: non_neg_integer()}]
        }

  @visit_gap_minutes 30
  @top_list_limit 10

  @spec summary(Config.t(), Period.range(), DateTime.t()) :: summary()
  def summary(%Config{} = conf, range, %DateTime{} = now) do
    period = Period.new(range, now)

    conf
    |> totals(period)
    |> Map.merge(visit_metrics(conf, period))
    |> Map.merge(%{
      top_pages: top_pages(conf, period),
      top_sources: top_sources(conf, period),
      series: series(conf, period)
    })
  end

  @spec record_pageviews(Config.t(), [captured_pageview()]) :: non_neg_integer()
  def record_pageviews(%Config{}, []), do: 0

  def record_pageviews(%Config{repo: repo, prefix: prefix} = conf, captured_pageviews) do
    salts = Salt.for_days(conf, Enum.map(captured_pageviews, &utc_day/1))

    {inserted, _returned} =
      repo.insert_all(Pageview, Enum.map(captured_pageviews, &pageview_row(&1, salts)), prefix: prefix)

    inserted
  end

  @spec prune(Config.t(), DateTime.t()) :: %{pageviews: non_neg_integer(), salts: non_neg_integer()}
  def prune(%Config{analytics_retention_days: analytics_retention_days} = conf, %DateTime{} = now) do
    yesterday = now |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date() |> Date.add(-1)

    cutoff = DateTime.shift(now, day: -analytics_retention_days)

    %{
      pageviews: BatchDelete.delete_older_than(conf, %{schema: Pageview, timestamp: :occurred_at, cutoff: cutoff}),
      salts: delete_salts_before(conf, yesterday)
    }
  end

  defp totals(%Config{repo: repo, prefix: prefix}, period) do
    period
    |> pageviews_in()
    |> select([pageview: pageview], %{
      visitors: count(pageview.visitor_id, :distinct),
      pageviews: count(pageview.id)
    })
    |> repo.one(prefix: prefix)
  end

  defp visit_metrics(%Config{repo: repo, prefix: prefix}, period) do
    period
    |> visits()
    |> subquery()
    |> from(as: :visit)
    |> select([visit: visit], %{
      visits: count(),
      bounces: filter(count(), visit.pageviews == 1),
      average_duration: type(avg(visit.duration_seconds), :float)
    })
    |> repo.one(prefix: prefix)
    |> rated_visits()
  end

  defp rated_visits(%{visits: 0}), do: %{visits: 0, bounce_rate: 0, visit_duration: 0}

  defp rated_visits(%{visits: visits, bounces: bounces, average_duration: average_duration}) do
    %{visits: visits, bounce_rate: round(bounces * 100 / visits), visit_duration: round(average_duration)}
  end

  defp visits(period) do
    period
    |> pageviews_with_previous()
    |> subquery()
    |> from(as: :timed_pageview)
    |> windows([timed_pageview: timed_pageview],
      visitor_timeline: [
        partition_by: timed_pageview.visitor_id,
        order_by: [timed_pageview.occurred_at, timed_pageview.id]
      ]
    )
    |> select([timed_pageview: timed_pageview], %{
      visitor_id: timed_pageview.visitor_id,
      occurred_at: timed_pageview.occurred_at,
      visit_number:
        over(
          sum(
            fragment(
              "CASE WHEN ? THEN 1 ELSE 0 END",
              is_nil(timed_pageview.previous_occurred_at) or
                timed_pageview.occurred_at >
                  datetime_add(timed_pageview.previous_occurred_at, @visit_gap_minutes, "minute")
            )
          ),
          :visitor_timeline
        )
    })
    |> subquery()
    |> from(as: :numbered_pageview)
    |> group_by([numbered_pageview: numbered_pageview], [numbered_pageview.visitor_id, numbered_pageview.visit_number])
    |> select([numbered_pageview: numbered_pageview], %{
      pageviews: count(),
      duration_seconds:
        type(
          fragment(
            "EXTRACT(EPOCH FROM max(?) - min(?))",
            numbered_pageview.occurred_at,
            numbered_pageview.occurred_at
          ),
          :float
        )
    })
  end

  defp pageviews_with_previous(period) do
    period
    |> pageviews_in()
    |> windows([pageview: pageview],
      visitor_timeline: [partition_by: pageview.visitor_id, order_by: [pageview.occurred_at, pageview.id]]
    )
    |> select([pageview: pageview], %{
      id: pageview.id,
      visitor_id: pageview.visitor_id,
      occurred_at: pageview.occurred_at,
      previous_occurred_at: over(lag(pageview.occurred_at), :visitor_timeline)
    })
  end

  defp top_pages(%Config{repo: repo, prefix: prefix}, period) do
    period
    |> pageviews_in()
    |> group_by([pageview: pageview], pageview.path)
    |> select([pageview: pageview], %{
      path: pageview.path,
      visitors: selected_as(count(pageview.visitor_id, :distinct), :visitors),
      pageviews: selected_as(count(pageview.id), :pageviews)
    })
    |> most_visited()
    |> order_by([pageview: pageview], asc: pageview.path)
    |> repo.all(prefix: prefix)
  end

  defp top_sources(%Config{repo: repo, prefix: prefix}, period) do
    period
    |> pageviews_in()
    |> group_by([pageview: pageview], pageview.source)
    |> select([pageview: pageview], %{
      source: pageview.source,
      visitors: selected_as(count(pageview.visitor_id, :distinct), :visitors),
      pageviews: selected_as(count(pageview.id), :pageviews)
    })
    |> most_visited()
    |> order_by([pageview: pageview], asc: pageview.source)
    |> repo.all(prefix: prefix)
  end

  defp most_visited(query) do
    query
    |> order_by(desc: selected_as(:visitors), desc: selected_as(:pageviews))
    |> limit(@top_list_limit)
  end

  defp series(%Config{repo: repo, prefix: prefix}, %{bucket: bucket, bucket_starts: bucket_starts} = period) do
    visitors_by_bucket =
      period
      |> pageviews_in()
      |> select([pageview: pageview], %{
        starts_at:
          selected_as(
            type(fragment("date_trunc(?, ?)", ^Atom.to_string(bucket), pageview.occurred_at), :utc_datetime),
            :starts_at
          ),
        visitors: count(pageview.visitor_id, :distinct)
      })
      |> group_by(selected_as(:starts_at))
      |> repo.all(prefix: prefix)
      |> Map.new(&{&1.starts_at, &1.visitors})

    Enum.map(bucket_starts, &%{starts_at: &1, visitors: Map.get(visitors_by_bucket, &1, 0)})
  end

  defp pageviews_in(%{starts_at: starts_at, ends_at: ends_at}) do
    Pageview
    |> from(as: :pageview)
    |> where([pageview: pageview], pageview.occurred_at >= ^starts_at and pageview.occurred_at <= ^ends_at)
  end

  defp delete_salts_before(%Config{repo: repo, prefix: prefix}, day) do
    {deleted, _rows} =
      Salt
      |> from(as: :salt)
      |> where([salt: salt], salt.day < ^day)
      |> repo.delete_all(prefix: prefix)

    deleted
  end

  defp pageview_row(captured_pageview, salts) do
    %{
      visitor_id:
        Visitor.id(%{
          salt: Map.fetch!(salts, utc_day(captured_pageview)),
          ip: captured_pageview.ip,
          user_agent: captured_pageview.user_agent
        }),
      path: path_without_query(captured_pageview.path),
      source: Source.from_referrer(captured_pageview.referrer, captured_pageview.host),
      occurred_at: utc_occurred_at(captured_pageview)
    }
  end

  defp utc_day(captured_pageview) do
    captured_pageview
    |> utc_occurred_at()
    |> DateTime.to_date()
  end

  defp utc_occurred_at(%{occurred_at: occurred_at}) do
    %DateTime{microsecond: {microsecond, _precision}} = utc_time = DateTime.shift_zone!(occurred_at, "Etc/UTC")
    %{utc_time | microsecond: {microsecond, 6}}
  end

  defp path_without_query(path) do
    path
    |> String.split(["?", "#"], parts: 2)
    |> hd()
  end
end
