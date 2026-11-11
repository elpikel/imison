defmodule Imison.Web.Auth do
  @moduledoc false

  alias Imison.Config

  @spec valid_credentials?(Config.t(), term(), term()) :: boolean()
  def valid_credentials?(%Config{} = config, username, password) when is_binary(username) and is_binary(password) do
    username_matches? = Plug.Crypto.secure_compare(username, config.username)
    password_matches? = Plug.Crypto.secure_compare(password, config.password)

    username_matches? and password_matches?
  end

  def valid_credentials?(%Config{}, _username, _password), do: false
end
