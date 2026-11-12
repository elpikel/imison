defmodule Imison.Notifications.Notifier do
  @moduledoc false

  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Notifications
  alias Imison.Notifications.ReminderMemo
  alias Imison.Notifications.Rule
  alias Imison.Registry

  @task_supervisor Imison.Notifications.TaskSupervisor
  @start_failure "Imison failed to start delivering notifications"

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %Config{name: name} = Keyword.fetch!(opts, :conf)

    Supervisor.child_spec({Task.Supervisor, name: Registry.via(name, @task_supervisor)}, id: __MODULE__)
  end

  @spec recorded(Config.t(), Error.t(), ReminderMemo.t()) :: ReminderMemo.t()
  def recorded(%Config{} = conf, %Error{} = error, %ReminderMemo{} = reminders) do
    case triggers(error) do
      [:still_happening] ->
        remind_unless_handed_off(conf, error, reminders)

      triggers ->
        Enum.each(triggers, &notify_in_background(conf, error, &1))
        reminders
    end
  end

  @spec triggers(Error.t()) :: [Rule.trigger()]
  def triggers(%Error{muted: true}), do: []
  def triggers(%Error{created: true}), do: [:new]
  def triggers(%Error{reopened: true}), do: [:regression]
  def triggers(%Error{status: :unresolved}), do: [:still_happening]
  def triggers(%Error{}), do: []

  defp remind_unless_handed_off(conf, error, reminders) do
    case ReminderMemo.hand_off(reminders, error) do
      {:hand_off, reminders} ->
        notify_in_background(conf, error, :still_happening)
        reminders

      {:already_handed_off, reminders} ->
        reminders
    end
  end

  defp notify_in_background(%Config{name: name} = conf, error, trigger) do
    with {task_supervisor, _value} <- Registry.lookup(name, @task_supervisor),
         {:error, reason} <- Task.Supervisor.start_child(task_supervisor, fn -> notify(conf, error, trigger) end) do
      FailureLog.error(@start_failure, %{kind: :error, reason: reason, stacktrace: []})
    end

    :ok
  catch
    kind, reason -> FailureLog.error(@start_failure, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  defp notify(conf, error, trigger) do
    Notifications.notify(conf, error, trigger)
  catch
    kind, reason ->
      FailureLog.error("Imison failed to send notifications", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end
end
