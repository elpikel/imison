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

  The dashboard's Notifications screen shows one panel per channel, titled
  by the optional `c:label/0` (else `c:type/0`), under it the optional
  `c:describe/1`, and a form field per entry of the optional
  `c:config_fields/0` (none without it), with an on/off switch, Save and
  "Send test". Saving stores the fields' values in the channel's `config`
  under their names, after `validate_config/1`; settings the fields don't
  list are kept. A `:secret` field is never shown back: the screen says a
  value is set, and leaving it blank keeps the stored value.
  """

  alias Imison.Config
  alias Imison.Notifications.Message

  @typedoc """
  One setting on the channel's panel. `name` is its key in the channel's
  `config`; `type` decides the input and the stored value:

    * `:recipients`: a textarea of values separated by commas or new lines,
      stored as a list of strings (blanks and repeats dropped)
    * `:text`: a text input, stored as a trimmed string (removed when blank)
    * `:url`: a URL input, stored like `:text`
    * `:secret`: a password input, stored like `:text`, never shown back;
      blank keeps the stored value

  `hint` is optional help shown under the field.
  """
  @type config_field :: %{
          required(:name) => String.t(),
          required(:label) => String.t(),
          required(:type) => :recipients | :text | :url | :secret,
          optional(:hint) => String.t()
        }

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

  Besides messages about one error, a channel receives the daily digest
  (`trigger: :digest`) when the `digest` rule is on: its error fields are
  `nil` and its `summary` is set (see `Imison.Notifications.Message`). A
  channel must render it or skip it (return `:ok` without sending), and
  must not assume a message's error fields are set.
  """
  @callback deliver(Message.t(), channel_config :: map(), Config.t()) :: :ok | {:error, term()}

  @doc """
  The title of the channel's panel on the Notifications screen, e.g.
  `"Email"`. Defaults to `c:type/0`.
  """
  @callback label() :: String.t()

  @doc """
  The settings the channel's panel asks for, in order; see
  `t:config_field/0`. Defaults to none.
  """
  @callback config_fields() :: [config_field()]

  @doc """
  A line under the panel's title, from the instance's config, e.g. which
  mailer sends the email. Defaults to none.
  """
  @callback describe(Config.t()) :: String.t()

  @optional_callbacks label: 0, config_fields: 0, describe: 1

  @doc false
  @spec label(module()) :: String.t()
  def label(channel_module) do
    if implements?(channel_module, :label, 0), do: channel_module.label(), else: channel_module.type()
  end

  @doc false
  @spec config_fields(module()) :: [config_field()]
  def config_fields(channel_module) do
    if implements?(channel_module, :config_fields, 0), do: channel_module.config_fields(), else: []
  end

  @doc false
  @spec describe(module(), Config.t()) :: String.t() | nil
  def describe(channel_module, %Config{} = conf) do
    if implements?(channel_module, :describe, 1), do: channel_module.describe(conf)
  end

  defp implements?(channel_module, function, arity) do
    Code.ensure_loaded?(channel_module) and function_exported?(channel_module, function, arity)
  end
end
