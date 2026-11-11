defmodule Imison.Test.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :imison, adapter: Ecto.Adapters.Postgres
end
