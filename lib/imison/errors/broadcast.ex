defmodule Imison.Errors.Broadcast do
  @moduledoc false

  alias Imison.Capture.FailureLog
  alias Imison.Config

  @type recorded_message :: {:imison, :recorded, pos_integer()}
  @type changed_message :: {:imison, :changed, [pos_integer()]}

  @spec subscribe(Config.t()) :: :ok | :no_pubsub | {:error, term()}
  def subscribe(%Config{pubsub: nil}), do: :no_pubsub

  def subscribe(%Config{pubsub: pubsub, name: name}) do
    Phoenix.PubSub.subscribe(pubsub, topic(name))
  rescue
    exception ->
      FailureLog.error("Imison failed to subscribe to recorded errors", %{
        kind: :error,
        reason: exception,
        stacktrace: __STACKTRACE__
      })

      {:error, exception}
  end

  @spec recorded(Config.t(), pos_integer()) :: :ok | {:error, term()}
  def recorded(%Config{pubsub: nil}, _error_id), do: :ok

  def recorded(%Config{pubsub: pubsub, name: name}, error_id) do
    Phoenix.PubSub.broadcast(pubsub, topic(name), {:imison, :recorded, error_id})
  end

  @spec changed(Config.t(), [pos_integer()]) :: :ok | {:error, term()}
  def changed(%Config{pubsub: nil}, _error_ids), do: :ok

  def changed(%Config{pubsub: pubsub, name: name}, error_ids) do
    Phoenix.PubSub.broadcast(pubsub, topic(name), {:imison, :changed, error_ids})
  end

  defp topic(name), do: "imison:" <> inspect(name)
end
