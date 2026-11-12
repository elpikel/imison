defmodule Imison.Notifications.Channel do
  @moduledoc """
  A way of delivering notifications, such as `Imison.Notifications.Channels.Email`.

  List channel modules in the `channels` option; the default holds only the
  email channel when Swoosh is available. A host app can add its own module
  implementing this behaviour without a new Imison release.

  Each channel's settings (`config`, e.g. the email recipients) are stored
  in the database under its `type/0`, and a channel is used only when they
  are enabled and pass `validate_config/1`. Rules and delivery records live
  in Imison, not in the channels: a channel only renders and sends one
  `Imison.Notifications.Message`.
  """

  alias Imison.Config
  alias Imison.Notifications.Message

  @doc """
  Keys the channel's stored settings, so one row in `imison_channels` holds
  them per channel, e.g. `"email"`.
  """
  @callback type() :: String.t()

  @doc """
  Checks the channel's stored settings: `:ok` when it can deliver with them,
  otherwise the reasons keyed by setting.
  """
  @callback validate_config(channel_config :: map()) :: :ok | {:error, keyword()}

  @doc """
  Delivers `message` with the channel's stored settings and the instance's
  config (which holds, e.g., the host's `mailer` and the `from` address).

  Returns `{:error, reason}` when it fails; Imison logs it and records the
  delivery as failed. An exception is treated the same way.
  """
  @callback deliver(Message.t(), channel_config :: map(), Config.t()) :: :ok | {:error, term()}
end
