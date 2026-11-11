defmodule Imison.Web.Auth do
  @moduledoc false

  import Plug.Conn

  alias Imison.Config
  alias Imison.Web.Paths
  alias Phoenix.LiveView

  @session_key "imison_auth"
  @session_token_salt "imison dashboard session"

  @spec valid_credentials?(Config.t(), term(), term()) :: boolean()
  def valid_credentials?(%Config{} = config, username, password) when is_binary(username) and is_binary(password) do
    username_matches? = Plug.Crypto.secure_compare(username, config.username)
    password_matches? = Plug.Crypto.secure_compare(password, config.password)

    username_matches? and password_matches?
  end

  def valid_credentials?(%Config{}, _username, _password), do: false

  @spec sign_in(Plug.Conn.t(), Config.t()) :: Plug.Conn.t()
  def sign_in(conn, %Config{} = config) do
    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, session_token(config, conn.secret_key_base))
  end

  @spec sign_out(Plug.Conn.t()) :: Plug.Conn.t()
  def sign_out(conn), do: delete_session(conn, @session_key)

  @spec on_mount(:require_sign_in, map() | :not_mounted_at_router, map(), LiveView.Socket.t()) ::
          {:cont | :halt, LiveView.Socket.t()}
  def on_mount(
        :require_sign_in,
        _params,
        %{"imison_name" => imison_name, "dashboard_path" => dashboard_path} = session,
        socket
      ) do
    config = Imison.config(imison_name)
    secret_key_base = socket.endpoint.config(:secret_key_base)

    if signed_in?(config, session[@session_key], secret_key_base) do
      {:cont, socket}
    else
      {:halt, LiveView.redirect(socket, to: Paths.login(dashboard_path))}
    end
  end

  defp signed_in?(%Config{} = config, session_token, secret_key_base) when is_binary(session_token),
    do: Plug.Crypto.secure_compare(session_token, session_token(config, secret_key_base))

  defp signed_in?(%Config{}, _session_token, _secret_key_base), do: false

  defp session_token(%Config{username: username, password: password}, secret_key_base) do
    key = :crypto.mac(:hmac, :sha256, secret_key_base, @session_token_salt)

    :hmac
    |> :crypto.mac(:sha256, key, username <> <<0>> <> password)
    |> Base.url_encode64(padding: false)
  end
end
