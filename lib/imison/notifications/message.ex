defmodule Imison.Notifications.Message do
  @moduledoc """
  The channel-neutral content of one notification, handed to a channel's
  `c:Imison.Notifications.Channel.deliver/3`.

  `trigger` is what the notification is about (`:new` for an error seen for
  the first time, `:regression` for a resolved error that came back);
  `regressed_at` is when the error last came back, `nil` if it never did;
  `url` is the link to the error's detail page on the dashboard, `nil` when
  the `dashboard_url` option isn't set.
  """

  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Notifications.Rule
  alias Imison.Web.Paths

  @type t :: %__MODULE__{
          trigger: Rule.trigger(),
          error_id: pos_integer(),
          kind: String.t(),
          message: String.t(),
          location: String.t() | nil,
          occurrence_count: pos_integer(),
          first_seen_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          regressed_at: DateTime.t() | nil,
          url: String.t() | nil
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
    :url
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

  defp error_url(nil, _error_id), do: nil
  defp error_url(dashboard_url, error_id), do: Paths.error(dashboard_url, error_id)
end
