defmodule Imison.Notifications do
  @moduledoc false

  import Ecto.Query

  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Notifications.ChannelSetting
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Message
  alias Imison.Notifications.Rule

  @spec put_channel(Config.t(), String.t(), map()) :: {:ok, ChannelSetting.t()} | {:error, Ecto.Changeset.t()}
  def put_channel(%Config{repo: repo, prefix: prefix}, type, attrs) do
    %ChannelSetting{type: type}
    |> ChannelSetting.changeset(attrs)
    |> repo.insert(
      prefix: prefix,
      on_conflict: {:replace, [:enabled, :config, :updated_at]},
      conflict_target: :type,
      returning: true
    )
  end

  @spec put_rule(Config.t(), Rule.trigger(), boolean()) :: {:ok, Rule.t()}
  def put_rule(%Config{repo: repo, prefix: prefix}, trigger, enabled) when is_boolean(enabled) do
    repo.insert(
      %Rule{trigger: trigger, enabled: enabled},
      prefix: prefix,
      on_conflict: {:replace, [:enabled, :updated_at]},
      conflict_target: :trigger,
      returning: true
    )
  end

  @spec channel_setting(Config.t(), String.t()) :: ChannelSetting.t() | nil
  def channel_setting(%Config{repo: repo, prefix: prefix}, type) do
    ChannelSetting
    |> from(as: :channel)
    |> where([channel: channel], channel.type == ^type)
    |> repo.one(prefix: prefix)
  end

  @spec put_channel_and_rules(Config.t(), module(), %{config: map(), rules: %{Rule.trigger() => boolean()}}) ::
          {:ok, ChannelSetting.t()} | {:error, {:invalid_config, keyword()}}
  def put_channel_and_rules(%Config{repo: repo} = conf, channel_module, %{config: channel_config, rules: rules}) do
    with :ok <- validate_channel_config(channel_module, channel_config) do
      repo.transact(fn ->
        store_channel_and_rules(conf, channel_module.type(), %{config: channel_config, rules: rules})
      end)
    end
  end

  @spec send_test(Config.t(), module(), map()) :: :ok | {:error, {:invalid_config, keyword()}} | {:error, term()}
  def send_test(%Config{} = conf, channel_module, channel_config) do
    with :ok <- validate_channel_config(channel_module, channel_config) do
      attempt_delivery(conf, %{module: channel_module, config: channel_config}, Message.test())
    end
  end

  @spec rule_enabled?(Config.t(), Rule.trigger()) :: boolean()
  def rule_enabled?(%Config{repo: repo, prefix: prefix}, trigger) do
    Rule
    |> from(as: :rule)
    |> where([rule: rule], rule.trigger == ^trigger)
    |> select([rule: rule], rule.enabled)
    |> repo.one(prefix: prefix)
    |> case do
      nil -> Rule.enabled_without_a_stored_rule?(trigger)
      enabled -> enabled
    end
  end

  @spec notify(Config.t(), Error.t(), Rule.trigger()) :: :ok
  def notify(%Config{} = conf, %Error{} = error, trigger) do
    if rule_enabled?(conf, trigger) do
      message = Message.new(conf, error, trigger)
      conf |> usable_channels() |> Enum.each(&deliver(conf, &1, message))
    end

    :ok
  end

  defp usable_channels(%Config{channels: channel_modules} = conf) do
    settings_by_type = conf |> enabled_channel_settings(Enum.map(channel_modules, & &1.type())) |> Map.new(&{&1.type, &1})

    for module <- channel_modules,
        setting = Map.get(settings_by_type, module.type()),
        setting != nil,
        module.validate_config(setting.config) == :ok,
        do: %{module: module, setting: setting}
  end

  defp enabled_channel_settings(%Config{repo: repo, prefix: prefix}, types) do
    ChannelSetting
    |> from(as: :channel)
    |> where([channel: channel], channel.enabled and channel.type in ^types)
    |> repo.all(prefix: prefix)
  end

  defp store_channel_and_rules(conf, type, %{config: channel_config, rules: rules}) do
    {:ok, channel} = put_channel(conf, type, %{enabled: true, config: channel_config})
    Enum.each(rules, fn {trigger, enabled} -> {:ok, _rule} = put_rule(conf, trigger, enabled) end)
    {:ok, channel}
  end

  defp validate_channel_config(channel_module, channel_config) do
    with {:error, reasons} <- channel_module.validate_config(channel_config) do
      {:error, {:invalid_config, reasons}}
    end
  end

  defp deliver(%Config{} = conf, %{module: module, setting: setting}, %Message{} = message) do
    outcome = attempt_delivery(conf, %{module: module, config: setting.config}, message)
    record_delivery(conf, setting, %{message: message, status: Delivery.status(outcome)})
  end

  defp attempt_delivery(conf, %{module: module, config: channel_config}, message) do
    with {:error, reason} <- module.deliver(message, channel_config, conf) do
      FailureLog.error(delivery_failure(module), %{kind: :error, reason: reason, stacktrace: []})
      {:error, reason}
    end
  catch
    kind, reason ->
      FailureLog.error(delivery_failure(module), %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
      {:error, reason}
  end

  defp delivery_failure(module), do: "Imison failed to deliver a notification through #{inspect(module)}"

  defp record_delivery(%Config{repo: repo, prefix: prefix}, %ChannelSetting{id: channel_id}, %{
         message: message,
         status: status
       }) do
    repo.insert!(
      %Delivery{
        channel_id: channel_id,
        error_id: message.error_id,
        trigger: message.trigger,
        status: status,
        sent_at: DateTime.utc_now()
      },
      prefix: prefix
    )
  end
end
