defmodule Imison.Web.Layouts do
  @moduledoc """
  The dashboard's root layout, which loads Imison's own assets, and the app
  shell shared by its pages, with the markup of `docs/design/`.
  """

  use Phoenix.Component

  alias Imison.Web.Assets
  alias Imison.Web.Paths
  alias Phoenix.LiveView.Rendered

  @doc """
  The HTML document around every dashboard page.
  """
  @spec root(map()) :: Rendered.t()
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <.live_title default="Imison" suffix=" – Imison">{assigns[:page_title]}</.live_title>
        <link rel="stylesheet" href={Assets.path(@dashboard_path, :stylesheet)} />
        <script defer src={Assets.path(@dashboard_path, :script)}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  The top bar with the main navigation, the Live indicator when `live` is
  true, and the Sign out button, and the page below it, headed by the
  `info` and `error` flash messages.
  """
  attr(:dashboard_path, :string, required: true)
  attr(:flash, :map, default: %{})
  attr(:live, :boolean, default: false)
  slot(:inner_block, required: true)

  @spec app(map()) :: Rendered.t()
  def app(assigns) do
    ~H"""
    <header class="topbar">
      <.link class="brand" navigate={@dashboard_path}>
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
      </.link>
      <nav class="nav" aria-label="Main">
        <.link class="nav__link" navigate={@dashboard_path} aria-current="page">Errors</.link>
      </nav>
      <div class="topbar__end">
        <span :if={@live} class="live" title="Connected. New events appear without reloading.">
          <span class="live__dot"></span><span>Live</span>
        </span>
        <.form for={%{}} action={Paths.logout(@dashboard_path)} method="post">
          <button class="btn btn--quiet btn--sm" type="submit">Sign out</button>
        </.form>
      </div>
    </header>
    <main class="page">
      <p :if={info = Phoenix.Flash.get(@flash, :info)} class="flash flash--info" role="status">{info}</p>
      <p :if={error = Phoenix.Flash.get(@flash, :error)} class="flash flash--error" role="alert">{error}</p>
      {render_slot(@inner_block)}
    </main>
    """
  end
end
