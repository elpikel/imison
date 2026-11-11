defmodule Imison.Test.CaptureHelpers do
  @moduledoc """
  Builders for capture tests: start an instance, wait for its worker to
  record what was cast to it, and read back what was recorded.
  """

  import Ecto.Query

  alias Imison.Capture.Worker
  alias Imison.Errors.Error
  alias Imison.Errors.Occurrence
  alias Imison.Test.Repo

  @spec start_imison(keyword()) :: reference()
  def start_imison(opts \\ []) do
    name = make_ref()
    ExUnit.Callbacks.start_supervised!({Imison, [name: name, repo: Repo, username: "admin", password: "secret"] ++ opts})
    name
  end

  @spec wait_for_worker(Imison.name()) :: term()
  def wait_for_worker(name) do
    name
    |> Imison.Registry.via(Worker)
    |> :sys.get_state()
  end

  @spec raised(String.t()) :: {Exception.t(), Exception.stacktrace()}
  def raised(message) do
    raise message
  rescue
    exception -> {exception, __STACKTRACE__}
  end

  @spec recorded(String.t()) :: [map()]
  def recorded(message) do
    Error
    |> from(as: :error)
    |> join(:inner, [error: error], occurrence in Occurrence, on: occurrence.error_id == error.id, as: :occurrence)
    |> where([error: error], error.message == ^message)
    |> select([error: error, occurrence: occurrence], %{
      kind: error.kind,
      occurrence_count: error.occurrence_count,
      stacktrace: occurrence.stacktrace,
      context: occurrence.context
    })
    |> Repo.all()
  end

  @spec unique_message() :: String.t()
  def unique_message, do: "crash #{System.unique_integer([:positive])}"
end
