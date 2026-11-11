defmodule Imison.Web.SessionHTML do
  @moduledoc """
  The login page (`docs/design/login.html`): the sign-in form over a mosaic of heat cells.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.Rendered

  @mosaic_cell_count 1500

  @doc """
  The sign-in form, with `error` shown above it after a failed attempt.
  """
  attr(:login_path, :string, required: true)
  attr(:error, :string, default: nil)

  @spec new(map()) :: Rendered.t()
  def new(assigns) do
    ~H"""
    <main class="auth">
      <.form for={%{}} class="panel auth__card" action={@login_path} method="post">
        <a class="brand" href={@login_path}>
          <svg class="brand__mark" viewBox="0 0 24 24" aria-hidden="true">
            <rect width="24" height="24" rx="7" style="fill:var(--mark)" />
            <path
              d="M5 14h4l2-6 3 9 2-5h3"
              fill="none"
              style="stroke:var(--spark)"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>Imison
        </a>
        <h1 class="auth__title">Sign in</h1>
        <p class="auth__lede">Errors caught in this app.</p>
        <p :if={@error} class="flash flash--error" role="alert">{@error}</p>
        <div class="field">
          <label class="field__label" for="username">Username</label>
          <input class="input" id="username" name="username" autocomplete="username" required />
        </div>
        <div class="field">
          <label class="field__label" for="password">Password</label>
          <input
            class="input"
            id="password"
            name="password"
            type="password"
            autocomplete="current-password"
            required
          />
        </div>
        <div class="field">
          <button class="btn btn--primary btn--block" type="submit">Sign in</button>
        </div>
        <p class="auth__note">
          The login is set with <code>IMISON_USER</code>
          and <code>IMISON_PASSWORD</code>
          in this app’s environment.
        </p>
      </.form>
      <div class="mosaic" aria-hidden="true"><i :for={level <- mosaic_levels()} data-l={level}></i></div>
    </main>
    """
  end

  defp mosaic_levels, do: Enum.map(1..@mosaic_cell_count, &(&1 |> :erlang.phash2(100) |> heat_level()))

  defp heat_level(percentile) when percentile < 50, do: nil
  defp heat_level(percentile) when percentile < 75, do: 1
  defp heat_level(percentile) when percentile < 88, do: 2
  defp heat_level(percentile) when percentile < 96, do: 3
  defp heat_level(_percentile), do: 4
end
