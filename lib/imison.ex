defmodule Imison do
  @moduledoc """
  Error tracker that runs inside the host's Phoenix app.

  Add Imison to the host's supervision tree, after its repo:

      children = [
        MyApp.Repo,
        {Imison, Application.fetch_env!(:my_app, Imison)}
      ]

  with its options in the host's config:

      config :my_app, Imison,
        repo: MyApp.Repo,
        username: System.fetch_env!("IMISON_USER"),
        password: System.fetch_env!("IMISON_PASSWORD")

  `repo`, `username` and `password` are required. Every other option has a
  default, see `Imison.Config`. Imison refuses to start with an
  `ArgumentError` when an option is missing, unknown, duplicate or of the
  wrong type, so a bad config fails the host's boot.
  """

  use Supervisor

  alias Imison.Capture
  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Registry

  @type name :: term()

  @doc """
  Starts an Imison supervision tree, raising `ArgumentError` when the options are invalid.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    conf = Config.new(opts)

    Supervisor.start_link(__MODULE__, conf, name: Registry.via(conf.name, nil, conf))
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Supervisor
  def init(%Config{} = conf) do
    conf
    |> capture_children()
    |> Supervisor.init(strategy: :one_for_one)
  end

  @doc """
  Returns the config of a running Imison instance.

  ## Example

  The default instance:

      %Imison.Config{} = Imison.config()

  An instance started with a custom name:

      %Imison.Config{} = Imison.config(MyApp.Imison)
  """
  @spec config(name()) :: Config.t()
  def config(name \\ __MODULE__), do: Registry.config(name)

  @doc """
  Reports an exception the app rescued itself, so handled errors are tracked too.

  `metadata` (a map or a keyword list) is stored under `metadata` in the
  occurrence's context, with keys from the `filter` option replaced by
  `[FILTERED]`. A value that isn't an exception, such as an Erlang error
  term, is normalized to its exception first.

  The report goes to the default instance, named `Imison`. It is recorded in
  the background, like a captured crash: `report/3` always returns `:ok`, never
  raises and never blocks, and does nothing when no instance runs or the
  exception is listed in `ignore`.

  ## Example

      try do
        MyApp.Orders.charge(order)
      rescue
        exception ->
          Imison.report(exception, __STACKTRACE__, %{order_id: order.id})
          {:error, :charge_failed}
      end
  """
  @spec report(Exception.t() | term(), Exception.stacktrace(), map() | keyword()) :: :ok
  def report(exception, stacktrace, metadata \\ %{}) do
    event = Capture.event(%{kind: :error, reason: exception, stacktrace: stacktrace}, %{metadata: metadata_map(metadata)})

    Capture.capture(__MODULE__, event)
  catch
    kind, reason ->
      FailureLog.error("Imison failed to report an exception", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  defp capture_children(%Config{enabled: false}), do: []

  defp capture_children(%Config{} = conf) do
    [
      {Imison.Notifications.Notifier, conf: conf},
      {Imison.Capture.Worker, conf: conf},
      {Imison.Capture.Handlers, conf: conf},
      {Imison.Pruner, conf: conf},
      {Imison.Notifications.Digest, conf: conf}
    ]
  end

  defp metadata_map(metadata) when is_map(metadata), do: metadata
  defp metadata_map(metadata) when is_list(metadata), do: Map.new(metadata)
end
