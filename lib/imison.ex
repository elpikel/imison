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
    Supervisor.init([{Imison.Capture.Worker, conf: conf}, {Imison.Capture.Handlers, conf: conf}], strategy: :one_for_one)
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
end
