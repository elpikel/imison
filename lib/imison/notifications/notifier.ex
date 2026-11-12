defmodule Imison.Notifications.Notifier do
  @moduledoc false

  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Notifications
  alias Imison.Registry

  @task_supervisor Imison.Notifications.TaskSupervisor
  @start_failure "Imison failed to start delivering notifications"

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %Config{name: name} = Keyword.fetch!(opts, :conf)

    Supervisor.child_spec({Task.Supervisor, name: Registry.via(name, @task_supervisor)}, id: __MODULE__)
  end

  @spec recorded(Config.t(), Error.t()) :: :ok
  def recorded(%Config{} = conf, %Error{created: true} = error), do: notify_in_background(conf, error, :new)
  def recorded(%Config{}, %Error{}), do: :ok

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
