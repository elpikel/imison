defmodule Imison.Notifications.Message do
  @moduledoc """
  The channel-neutral content of one notification, handed to a channel's
  `c:Imison.Notifications.Channel.deliver/3`.

  `trigger` is what the notification is about (`:new` for an error seen for
  the first time, `:regression` for a resolved error that came back,
  `:still_happening` for the reminder, at most once an hour, about an
  unresolved error that keeps happening, `:digest` for the daily digest,
  `:test` for the test message sent from the notifications screen; the digest
  and the test message are about no single error, so their error fields are
  `nil`);
  `regressed_at` is when the error last came back, `nil` if it never did;
  `url` is the link to the error's detail page on the dashboard, `nil` when
  the `dashboard_url` option isn't set.

  `summary` is set only for the daily digest (and `nil` for every other
  message): the UTC `date` it covers, `url`, the dashboard's error list
  (`nil` without `dashboard_url`), and three sections: the errors first seen
  that day (`new`, oldest first), the errors that came back that day
  (`came_back`) and the errors that occurred most that day (`most_frequent`,
  most first). Each section is `%{lines: [...], total: n}`: `lines` holds at
  most 20 errors (5 for `most_frequent`) and `total` counts every error in
  the section that day (for `most_frequent`, every error that occurred), so
  a channel can say how many it left out. Each line has the error's
  `error_id`, `kind`, `message`, `location`, its occurrence `count` on that
  day and its `url` (`nil` without `dashboard_url`). Muted errors are listed
  too.
  """

  alias Imison.Config
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Notifications.Rule
  alias Imison.Web.Paths

  @type trigger :: Rule.trigger() | :test

  @type summary_line :: %{
          error_id: pos_integer(),
          kind: String.t(),
          message: String.t(),
          location: String.t() | nil,
          count: non_neg_integer(),
          url: String.t() | nil
        }

  @type summary_section :: %{lines: [summary_line()], total: non_neg_integer()}

  @type summary :: %{
          date: Date.t(),
          url: String.t() | nil,
          new: summary_section(),
          came_back: summary_section(),
          most_frequent: summary_section()
        }

  @type t :: %__MODULE__{
          trigger: trigger(),
          error_id: pos_integer() | nil,
          kind: String.t() | nil,
          message: String.t() | nil,
          location: String.t() | nil,
          occurrence_count: pos_integer() | nil,
          first_seen_at: DateTime.t() | nil,
          last_seen_at: DateTime.t() | nil,
          regressed_at: DateTime.t() | nil,
          url: String.t() | nil,
          summary: summary() | nil
        }

  @enforce_keys [:trigger, :error_id, :kind, :message, :occurrence_count, :first_seen_at, :last_seen_at]
  defstruct [
    :trigger,
    :error_id,
    :kind,
    :message,
    :location,
    :occurrence_count,
    :first_seen_at,
    :last_seen_at,
    :regressed_at,
    :url,
    :summary
  ]

  @doc false
  @spec new(Config.t(), Error.t(), Rule.trigger()) :: t()
  def new(%Config{dashboard_url: dashboard_url}, %Error{} = error, trigger) do
    %__MODULE__{
      trigger: trigger,
      error_id: error.id,
      kind: error.kind,
      message: error.message,
      location: error.location,
      occurrence_count: error.occurrence_count,
      first_seen_at: error.first_seen_at,
      last_seen_at: error.last_seen_at,
      regressed_at: error.regressed_at,
      url: error_url(dashboard_url, error.id)
    }
  end

  @doc false
  @spec test() :: t()
  def test do
    %__MODULE__{
      trigger: :test,
      error_id: nil,
      kind: nil,
      message: nil,
      occurrence_count: nil,
      first_seen_at: nil,
      last_seen_at: nil
    }
  end

  @doc false
  @spec digest(Config.t(), Errors.daily_summary()) :: t()
  def digest(%Config{dashboard_url: dashboard_url}, %{date: date} = daily_summary) do
    summary =
      daily_summary
      |> Map.take([:new, :came_back, :most_frequent])
      |> Map.new(fn {name, section} -> {name, with_error_urls(section, dashboard_url)} end)
      |> Map.merge(%{date: date, url: dashboard_url})

    %__MODULE__{
      trigger: :digest,
      error_id: nil,
      kind: nil,
      message: nil,
      occurrence_count: nil,
      first_seen_at: nil,
      last_seen_at: nil,
      summary: summary
    }
  end

  defp with_error_urls(%{lines: lines} = section, dashboard_url),
    do: %{section | lines: Enum.map(lines, &with_error_url(&1, dashboard_url))}

  defp with_error_url(line, dashboard_url), do: Map.put(line, :url, error_url(dashboard_url, line.error_id))

  defp error_url(nil, _error_id), do: nil
  defp error_url(dashboard_url, error_id), do: Paths.error(dashboard_url, error_id)
end
