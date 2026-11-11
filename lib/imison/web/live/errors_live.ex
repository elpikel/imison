defmodule Imison.Web.ErrorsLive do
  @moduledoc """
  The error list, the dashboard's home page (`docs/design/errors.html`).
  """

  use Phoenix.LiveView

  alias Imison.Web.Layouts

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    {:ok,
     assign(socket,
       conf: Imison.config(imison_name),
       dashboard_path: dashboard_path,
       page_title: "Errors"
     )}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app dashboard_path={@dashboard_path}>
      <div class="page__head">
        <div>
          <h1 class="page__title">Errors</h1>
        </div>
      </div>
      <section class="panel">
        <div class="empty">
          <h2 class="empty__title">No unresolved errors</h2>
          <p class="empty__text">New errors appear here as they happen.</p>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
