defmodule Imison.AnalyticsTest do
  use Imison.DataCase, async: false

  import Ecto.Query

  alias Imison.Analytics
  alias Imison.Analytics.Pageview
  alias Imison.Analytics.Salt
  alias Imison.Config
  alias Imison.Test.PrivatePrefix

  test "a recorded pageview is stored with its path and time" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(path: "/pricing", occurred_at: ~U[2026-11-16 10:15:00.000000Z])])

    assert [%Pageview{path: "/pricing", occurred_at: ~U[2026-11-16 10:15:00.000000Z]}] = Repo.all(Pageview)
  end

  test "a pageview time without microseconds is stored" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(occurred_at: ~U[2026-11-16 10:15:00Z])])

    assert [%Pageview{occurred_at: ~U[2026-11-16 10:15:00.000000Z]}] = Repo.all(Pageview)
  end

  test "every pageview of a batch is stored" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(path: "/"),
      captured_pageview(path: "/pricing"),
      captured_pageview(path: "/docs")
    ])

    assert Pageview |> Repo.all() |> Enum.map(& &1.path) |> Enum.sort() == ["/", "/docs", "/pricing"]
  end

  test "the query string is left out of the stored path" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(path: "/search?q=shoes#results")])

    assert [%Pageview{path: "/search"}] = Repo.all(Pageview)
  end

  test "a referrer from another host is the source, without www" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(referrer: "https://www.google.com/search?q=x", host: "shop.example.com")
    ])

    assert [%Pageview{source: "google.com"}] = Repo.all(Pageview)
  end

  test "the source host is downcased" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(referrer: "https://News.YCombinator.com/item?id=1")])

    assert [%Pageview{source: "news.ycombinator.com"}] = Repo.all(Pageview)
  end

  test "a pageview without a referrer has no source" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(referrer: nil), captured_pageview(referrer: "")])

    assert stored_sources() == [nil, nil]
  end

  test "a referrer from the app's own host is not a source, whatever its www or case" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(referrer: "https://shop.example.com/cart", host: "shop.example.com"),
      captured_pageview(referrer: "https://WWW.Shop.Example.com/cart", host: "shop.example.com"),
      captured_pageview(referrer: "https://shop.example.com/cart", host: "www.shop.example.com")
    ])

    assert stored_sources() == [nil, nil, nil]
  end

  test "a referrer without a host is not a source" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(referrer: "/relative/path"),
      captured_pageview(referrer: "not a url at all"),
      captured_pageview(referrer: "http://[broken")
    ])

    assert stored_sources() == [nil, nil, nil]
  end

  test "two pageviews on the same UTC day from the same IP and user agent have the same visitor" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(ip: "203.0.113.7", user_agent: firefox(), occurred_at: ~U[2026-11-16 00:05:00.000000Z])
    ])

    Analytics.record_pageviews(conf, [
      captured_pageview(ip: "203.0.113.7", user_agent: firefox(), occurred_at: ~U[2026-11-16 23:55:00.000000Z])
    ])

    assert [visitor_id, visitor_id] = visitor_ids()
  end

  test "pageviews that differ in IP or user agent have different visitors" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(ip: "203.0.113.7", user_agent: firefox()),
      captured_pageview(ip: "203.0.113.8", user_agent: firefox()),
      captured_pageview(ip: "203.0.113.7", user_agent: safari())
    ])

    assert visitor_ids() |> Enum.uniq() |> length() == 3
  end

  test "the same IP and user agent on a new UTC day is a different visitor" do
    conf = config()

    Analytics.record_pageviews(conf, [
      captured_pageview(ip: "203.0.113.7", user_agent: firefox(), occurred_at: ~U[2026-11-15 23:59:59.000000Z]),
      captured_pageview(ip: "203.0.113.7", user_agent: firefox(), occurred_at: ~U[2026-11-16 00:00:00.000000Z])
    ])

    assert [first_day_visitor, second_day_visitor] = visitor_ids()
    assert first_day_visitor != second_day_visitor
  end

  test "two nodes sharing the database store the same visitor for the same day" do
    first_node = config()
    second_node = config()

    Analytics.record_pageviews(first_node, [captured_pageview(ip: "203.0.113.7", user_agent: firefox())])

    second_node_process =
      Task.async(fn ->
        Analytics.record_pageviews(second_node, [captured_pageview(ip: "203.0.113.7", user_agent: firefox())])
      end)

    Task.await(second_node_process)

    assert [visitor_id, visitor_id] = visitor_ids()
  end

  test "the stored pageview holds neither the IP nor the user agent" do
    conf = config()

    Analytics.record_pageviews(conf, [captured_pageview(ip: "203.0.113.7", user_agent: firefox())])

    %{rows: [row]} = Repo.query!("SELECT * FROM imison_pageviews")
    stored_text = Enum.map_join(row, " ", &inspect/1)

    refute stored_text =~ "203.0.113.7"
    refute stored_text =~ "Firefox"
  end

  test "with a configured prefix pageviews and salts are stored in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())

    Analytics.record_pageviews(conf, [captured_pageview(path: "/pricing")])

    assert [%Pageview{path: "/pricing"}] = Repo.all(Pageview, prefix: PrivatePrefix.name())
    assert Repo.all(Pageview) == []

    assert %{rows: [[1]]} =
             Repo.query!("SELECT count(*)::int FROM #{PrivatePrefix.name()}.imison_salts")
  end

  test "visitors and pageviews count only the pageviews in the range" do
    conf = config()
    returning_visitor = visitor_id()
    store_pageview(%{visitor_id: returning_visitor, occurred_at: ~U[2026-11-16 09:00:00Z]})
    store_pageview(%{visitor_id: returning_visitor, occurred_at: ~U[2026-11-16 09:05:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 14:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-15 23:59:59Z]})

    assert %{visitors: 2, pageviews: 3} = Analytics.summary(conf, :today, now())
  end

  test "the last 7 days run from the start of the UTC day six days ago" do
    conf = config()
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-10 00:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-09 23:59:59Z]})

    assert %{visitors: 1, pageviews: 1} = Analytics.summary(conf, :last_7_days, now())
  end

  test "the last 30 days run from the start of the UTC day 29 days ago" do
    conf = config()
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-10-18 00:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-10-17 23:59:59Z]})

    assert %{visitors: 1, pageviews: 1} = Analytics.summary(conf, :last_30_days, now())
  end

  test "a gap of more than 30 minutes or another visitor starts a new visit" do
    conf = config()
    store_three_visits()

    assert %{visits: 3} = Analytics.summary(conf, :today, now())
  end

  test "pageviews exactly 30 minutes apart stay in one visit" do
    conf = config()
    visitor = visitor_id()
    store_pageview(%{visitor_id: visitor, occurred_at: ~U[2026-11-16 10:00:00Z]})
    store_pageview(%{visitor_id: visitor, occurred_at: ~U[2026-11-16 10:30:00Z]})

    assert %{visits: 1} = Analytics.summary(conf, :today, now())
  end

  test "the bounce rate is the rounded percentage of visits with a single pageview" do
    conf = config()
    store_three_visits()

    assert %{bounce_rate: 67} = Analytics.summary(conf, :today, now())
  end

  test "the visit duration is the average first-to-last pageview time per visit in seconds" do
    conf = config()
    store_three_visits()

    assert %{visit_duration: 200} = Analytics.summary(conf, :today, now())
  end

  test "top pages are ordered by visitors with their visitor and pageview counts" do
    conf = config()
    regular = visitor_id()
    store_pageview(%{visitor_id: regular, path: "/docs", occurred_at: ~U[2026-11-16 10:00:00Z]})
    store_pageview(%{visitor_id: regular, path: "/docs", occurred_at: ~U[2026-11-16 10:01:00Z]})
    store_pageview(%{visitor_id: regular, path: "/docs", occurred_at: ~U[2026-11-16 10:02:00Z]})
    store_pageview(%{visitor_id: visitor_id(), path: "/pricing", occurred_at: ~U[2026-11-16 11:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), path: "/pricing", occurred_at: ~U[2026-11-16 11:00:00Z]})

    assert %{
             top_pages: [
               %{path: "/pricing", visitors: 2, pageviews: 2},
               %{path: "/docs", visitors: 1, pageviews: 3}
             ]
           } = Analytics.summary(conf, :today, now())
  end

  test "top pages list at most 10 pages" do
    conf = config()

    for page <- 1..11 do
      store_pageview(%{visitor_id: visitor_id(), path: "/page-#{page}", occurred_at: ~U[2026-11-16 10:00:00Z]})
    end

    expected = 1..11 |> Enum.map(&"/page-#{&1}") |> Enum.sort() |> Enum.take(10)

    assert %{top_pages: top_pages} = Analytics.summary(conf, :today, now())
    assert Enum.map(top_pages, & &1.path) == expected
  end

  test "top sources are ordered by visitors, with pageviews without a source under a nil source" do
    conf = config()
    reader = visitor_id()
    store_pageview(%{visitor_id: reader, source: "google.com", occurred_at: ~U[2026-11-16 10:00:00Z]})
    store_pageview(%{visitor_id: reader, source: "google.com", occurred_at: ~U[2026-11-16 10:01:00Z]})
    store_pageview(%{visitor_id: visitor_id(), source: nil, occurred_at: ~U[2026-11-16 11:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), source: nil, occurred_at: ~U[2026-11-16 12:00:00Z]})

    assert %{
             top_sources: [
               %{source: nil, visitors: 2, pageviews: 2},
               %{source: "google.com", visitors: 1, pageviews: 2}
             ]
           } = Analytics.summary(conf, :today, now())
  end

  test "top sources list at most 10 sources" do
    conf = config()

    for source <- 1..11 do
      store_pageview(%{visitor_id: visitor_id(), source: "site-#{source}.com", occurred_at: ~U[2026-11-16 10:00:00Z]})
    end

    expected = 1..11 |> Enum.map(&"site-#{&1}.com") |> Enum.sort() |> Enum.take(10)

    assert %{top_sources: top_sources} = Analytics.summary(conf, :today, now())
    assert Enum.map(top_sources, & &1.source) == expected
  end

  test "today's chart has 24 hourly visitor counts in UTC, zero where there was no traffic" do
    conf = config()
    visitor = visitor_id()
    store_pageview(%{visitor_id: visitor, occurred_at: ~U[2026-11-16 09:10:00Z]})
    store_pageview(%{visitor_id: visitor, occurred_at: ~U[2026-11-16 09:50:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 09:59:59Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 00:00:00Z]})

    assert %{series: series} = Analytics.summary(conf, :today, now())

    assert series ==
             Enum.map(0..23, fn hour ->
               %{
                 starts_at: DateTime.new!(~D[2026-11-16], Time.new!(hour, 0, 0), "Etc/UTC"),
                 visitors: Map.get(%{0 => 1, 9 => 2}, hour, 0)
               }
             end)
  end

  test "the 7-day chart has one visitor count per UTC day, zero where there was no traffic" do
    conf = config()
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-10 00:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 15:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 01:00:00Z]})

    assert %{series: series} = Analytics.summary(conf, :last_7_days, now())

    assert series ==
             Enum.map(Date.range(~D[2026-11-10], ~D[2026-11-16]), fn day ->
               %{
                 starts_at: DateTime.new!(day, ~T[00:00:00], "Etc/UTC"),
                 visitors: Map.get(%{~D[2026-11-10] => 1, ~D[2026-11-16] => 2}, day, 0)
               }
             end)
  end

  test "the 30-day chart has one visitor count per UTC day" do
    conf = config()
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-10-18 08:00:00Z]})

    assert %{series: series} = Analytics.summary(conf, :last_30_days, now())

    assert series ==
             Enum.map(Date.range(~D[2026-10-18], ~D[2026-11-16]), fn day ->
               %{
                 starts_at: DateTime.new!(day, ~T[00:00:00], "Etc/UTC"),
                 visitors: if(day == ~D[2026-10-18], do: 1, else: 0)
               }
             end)
  end

  test "a range without pageviews reads as zeros and empty lists" do
    conf = config()

    assert %{
             visitors: 0,
             pageviews: 0,
             visits: 0,
             bounce_rate: 0,
             visit_duration: 0,
             top_pages: [],
             top_sources: [],
             series: series
           } = Analytics.summary(conf, :last_7_days, now())

    assert Enum.map(series, & &1.visitors) == [0, 0, 0, 0, 0, 0, 0]
  end

  test "with a configured prefix the metrics read that schema's pageviews" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 10:00:00Z]}, prefix: PrivatePrefix.name())
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 10:00:00Z]})

    assert %{visitors: 1, pageviews: 1, visits: 1, top_pages: [%{visitors: 1}], series: series} =
             Analytics.summary(conf, :today, now())

    assert series |> Enum.map(& &1.visitors) |> Enum.sum() == 1
  end

  test "pruning deletes pageviews older than the analytics retention days and keeps the newer ones" do
    conf = config(analytics_retention_days: 30)
    store_pageview(%{visitor_id: visitor_id(), path: "/old", occurred_at: DateTime.shift(now(), day: -31)})
    store_pageview(%{visitor_id: visitor_id(), path: "/recent", occurred_at: DateTime.shift(now(), day: -29)})

    Analytics.prune(conf, now())

    assert stored_paths() == ["/recent"]
  end

  test "pruning keeps a pageview exactly analytics retention days old and deletes one a second older" do
    conf = config(analytics_retention_days: 30)
    cutoff = DateTime.shift(now(), day: -30)
    store_pageview(%{visitor_id: visitor_id(), path: "/past-cutoff", occurred_at: DateTime.shift(cutoff, second: -1)})
    store_pageview(%{visitor_id: visitor_id(), path: "/at-cutoff", occurred_at: cutoff})

    Analytics.prune(conf, now())

    assert stored_paths() == ["/at-cutoff"]
  end

  test "pruning without an analytics_retention_days option keeps 90 days of pageviews" do
    conf = config()
    store_pageview(%{visitor_id: visitor_id(), path: "/old", occurred_at: DateTime.shift(now(), week: -13)})
    store_pageview(%{visitor_id: visitor_id(), path: "/recent", occurred_at: DateTime.shift(now(), day: -89)})

    Analytics.prune(conf, now())

    assert stored_paths() == ["/recent"]
  end

  test "pruning deletes salts older than yesterday and keeps yesterday's and today's" do
    conf = config()
    Salt.for_days(conf, [~D[2026-11-13], ~D[2026-11-14], ~D[2026-11-15], ~D[2026-11-16]])

    Analytics.prune(conf, now())

    assert stored_salt_days() == [~D[2026-11-15], ~D[2026-11-16]]
  end

  test "pruning reports how many pageviews and salts it deleted" do
    conf = config(analytics_retention_days: 30)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: DateTime.shift(now(), day: -31)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: DateTime.shift(now(), day: -40)})
    Salt.for_days(conf, [~D[2026-11-14], ~D[2026-11-16]])

    assert Analytics.prune(conf, now()) == %{pageviews: 2, salts: 1}
  end

  test "pruning deletes old pageviews and salts with analytics turned off" do
    conf = config(analytics: false, analytics_retention_days: 30)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: DateTime.shift(now(), day: -31)})
    Salt.for_days(conf, [~D[2026-11-14]])

    Analytics.prune(conf, now())

    assert stored_paths() == []
    assert stored_salt_days() == []
  end

  test "with a configured prefix old pageviews and salts are pruned in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name(), analytics_retention_days: 30)
    old_pageview = %{visitor_id: visitor_id(), occurred_at: DateTime.shift(now(), day: -31)}
    store_pageview(old_pageview, prefix: PrivatePrefix.name())
    store_pageview(old_pageview)
    Salt.for_days(conf, [~D[2026-11-14]])

    assert Analytics.prune(conf, now()) == %{pageviews: 1, salts: 1}

    assert Repo.all(Pageview, prefix: PrivatePrefix.name()) == []
    assert [%Pageview{}] = Repo.all(Pageview)
  end

  defp now, do: ~U[2026-11-16 15:30:00Z]

  defp stored_paths do
    Pageview
    |> from(as: :pageview)
    |> order_by([pageview: pageview], asc: pageview.path)
    |> select([pageview: pageview], pageview.path)
    |> Repo.all()
  end

  defp stored_salt_days do
    Salt
    |> from(as: :salt)
    |> order_by([salt: salt], asc: salt.day)
    |> select([salt: salt], salt.day)
    |> Repo.all()
  end

  defp store_three_visits do
    two_visits = visitor_id()
    store_pageview(%{visitor_id: two_visits, occurred_at: ~U[2026-11-16 10:00:00Z]})
    store_pageview(%{visitor_id: two_visits, occurred_at: ~U[2026-11-16 10:10:00Z]})
    store_pageview(%{visitor_id: two_visits, occurred_at: ~U[2026-11-16 11:00:00Z]})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: ~U[2026-11-16 10:05:00Z]})
  end

  defp store_pageview(attributes, opts \\ []) do
    pageview = Map.merge(%{path: "/", source: nil}, attributes)
    Repo.insert_all(Pageview, [%{pageview | occurred_at: %{pageview.occurred_at | microsecond: {0, 6}}}], opts)
  end

  defp visitor_id, do: System.unique_integer([:positive])

  defp config(opts \\ []) do
    [repo: Repo, username: "admin", password: "secret", analytics: true]
    |> Keyword.merge(opts)
    |> Config.new()
  end

  defp captured_pageview(attributes) do
    Map.merge(
      %{
        path: "/",
        referrer: nil,
        host: "shop.example.com",
        ip: "198.51.100.1",
        user_agent: firefox(),
        occurred_at: ~U[2026-11-16 10:00:00.000000Z]
      },
      Map.new(attributes)
    )
  end

  defp stored_sources do
    Pageview
    |> from(as: :pageview)
    |> order_by([pageview: pageview], asc: pageview.id)
    |> select([pageview: pageview], pageview.source)
    |> Repo.all()
  end

  defp visitor_ids do
    Pageview
    |> from(as: :pageview)
    |> order_by([pageview: pageview], asc: pageview.occurred_at, asc: pageview.id)
    |> select([pageview: pageview], pageview.visitor_id)
    |> Repo.all()
  end

  defp firefox, do: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:132.0) Gecko/20100101 Firefox/132.0"

  defp safari do
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
  end
end
