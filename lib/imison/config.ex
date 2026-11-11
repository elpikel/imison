defmodule Imison.Config do
  @moduledoc """
  The validated options of a running Imison instance.

  `new/1` fills in defaults for options left out and raises `ArgumentError`
  when an option is missing, unknown, duplicate or of the wrong type, so a
  host app with a bad config fails to boot.
  """

  alias Imison.Validation

  @type t :: %__MODULE__{
          name: term(),
          repo: module(),
          username: String.t(),
          password: String.t(),
          pubsub: atom() | nil,
          mailer: module() | nil,
          from: String.t() | nil,
          release: String.t() | nil,
          retention_days: pos_integer(),
          channels: [module()],
          enabled: boolean(),
          filter: [String.t()],
          ignore: [module()],
          prefix: String.t()
        }

  @required_options [:repo, :username, :password]

  @derive {Inspect, except: [:password]}
  @enforce_keys @required_options
  defstruct name: Imison,
            repo: nil,
            username: nil,
            password: nil,
            pubsub: nil,
            mailer: nil,
            from: nil,
            release: nil,
            retention_days: 30,
            channels: [],
            enabled: true,
            filter: ~w(password token secret authorization cookie),
            ignore: [],
            prefix: "public"

  @doc """
  Builds the config from the host's options, raising `ArgumentError` when they're invalid.
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    with {:error, reason} <- validate(opts) do
      raise ArgumentError, reason
    end

    struct!(__MODULE__, opts)
  end

  @doc """
  Checks the host's options without building the config.
  """
  @spec validate(keyword()) :: :ok | {:error, String.t()}
  def validate(opts) when is_list(opts) do
    with :ok <- validate_unique_options(opts),
         :ok <-
           Validation.validate_schema(opts,
             name: :any,
             repo: {:module, [config: 0]},
             username: :string,
             password: :string,
             pubsub: :atom,
             mailer: {:or, [nil, {:module, [deliver: 2]}]},
             from: {:or, [nil, :string]},
             release: {:or, [nil, :string]},
             retention_days: :pos_integer,
             channels: {:list, {:module, []}},
             enabled: :boolean,
             filter: {:list, :string},
             ignore: {:list, {:module, [exception: 1]}},
             prefix: :string
           ) do
      validate_required(opts)
    end
  end

  defp validate_unique_options(opts) do
    keys = Keyword.keys(opts)
    duplicates = keys -- Enum.uniq(keys)

    if Enum.empty?(duplicates) do
      :ok
    else
      {:error, "found duplicate options: #{inspect(duplicates)}"}
    end
  end

  defp validate_required(opts) do
    case Enum.reject(@required_options, &Keyword.has_key?(opts, &1)) do
      [] -> :ok
      [missing | _] -> {:error, "missing required option #{inspect(missing)}"}
    end
  end
end
