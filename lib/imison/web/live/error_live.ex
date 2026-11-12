defmodule Imison.Web.ErrorLive do
  @moduledoc """
  An error's detail page (`docs/design/error-detail.html`): its kind,
  message, location, status, occurrence count and first and last seen, then
  one occurrence's stack trace, request, Logger metadata and runtime. The
  occurrence is the one named by `?occurrence=<id>`, or the latest when the
  URL names none, names another error's occurrence or gives no number; Older
  and Newer step to its neighbours by patching the URL. Panels with nothing to show are
  left out, and an error without occurrences has no occurrence navigation. An
  unknown id sends the developer back to the list with a message.

  The summary rail offers the status changes: Resolve and Ignore for an
  unresolved error, Mark unresolved for a resolved or ignored one.
  """

  use Phoenix.LiveView

  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Errors.Occurrence
  alias Imison.Web.Format
  alias Imison.Web.Layouts
  alias Imison.Web.Paths

  @status_flags %{unresolved: "flag--unresolved", resolved: "flag--resolved", ignored: "flag--off"}
  @status_actions %{
    unresolved: [%{status: :resolved, label: "Resolve", style: "btn--primary"}, %{status: :ignored, label: "Ignore"}],
    resolved: [%{status: :unresolved, label: "Mark unresolved"}],
    ignored: [%{status: :unresolved, label: "Mark unresolved"}]
  }

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    conf = Imison.config(imison_name)
    socket = assign(socket, conf: conf, dashboard_path: dashboard_path)

    case Errors.get(conf, id) do
      %Error{} = error ->
        {:ok, assign(socket, page_title: error.kind, error: error)}

      nil ->
        {:ok, back_to_list(socket)}
    end
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, %{assigns: %{conf: conf, error: error}} = socket) do
    {:noreply, assign(socket, stepped_occurrence: Errors.occurrence(conf, error.id, params["occurrence"]))}
  end

  @impl Phoenix.LiveView
  def handle_event("set_status", params, %{assigns: %{conf: conf, error: error}} = socket) do
    with {:ok, _count} <- Errors.set_status(conf, [error.id], params["status"]),
         %Error{} = changed_error <- Errors.get(conf, error.id) do
      {:noreply, assign(socket, error: changed_error)}
    else
      {:error, :invalid_status} -> {:noreply, socket}
      nil -> {:noreply, back_to_list(socket)}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app dashboard_path={@dashboard_path} flash={@flash}>
      <.link class="back" navigate={@dashboard_path}>Back to errors</.link>
      <div class="detail">
        <div>
          <header class="error-head">
            <h1 class="error-head__kind">{@error.kind}</h1>
            <p class="error-head__message">{@error.message}</p>
            <div class="error-head__meta">
              <span class={["flag", status_flag(@error.status)]}>{Format.status_label(@error.status)}</span>
              <code :if={@error.location} class="error-head__location">{@error.location}</code>
            </div>
          </header>
          <%= if @stepped_occurrence do %>
            <.occurrence_navigation stepped_occurrence={@stepped_occurrence} error_path={Paths.error(@dashboard_path, @error.id)} />
            <.occurrence occurrence={@stepped_occurrence.occurrence} />
          <% end %>
        </div>
        <aside class="panel rail" aria-label="Error summary">
          <div class="rail__block">
            <div class="btn-row">
              <button
                :for={action <- status_actions(@error.status)}
                class={["btn", action[:style]]}
                type="button"
                phx-click="set_status"
                phx-value-status={action.status}
              >
                {action.label}
              </button>
            </div>
          </div>
          <div class="rail__block rail__stats">
            <div>
              <p class="rail__label">Events</p>
              <p class="rail__value">{Format.with_thousands_separators(@error.occurrence_count)}</p>
            </div>
          </div>
          <div class="rail__block">
            <p class="rail__label">First seen</p>
            <p class="rail__value">{Format.utc_time(@error.first_seen_at)}</p>
          </div>
          <div class="rail__block">
            <p class="rail__label">Last seen</p>
            <p class="rail__value">{Format.utc_time(@error.last_seen_at)}</p>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :stepped_occurrence, :map, required: true
  attr :error_path, :string, required: true

  defp occurrence_navigation(assigns) do
    ~H"""
    <section class="panel">
      <div class="panel__head occurrence-nav">
        <p class="occurrence-nav__when">
          <strong>Occurrence {@stepped_occurrence.position} of {@stepped_occurrence.total}</strong>
          <span class="muted">{Format.utc_time(@stepped_occurrence.occurrence.occurred_at)}</span>
        </p>
        <div class="btn-row">
          <.step label="Older" error_path={@error_path} occurrence_id={@stepped_occurrence.older_id} />
          <.step label="Newer" error_path={@error_path} occurrence_id={@stepped_occurrence.newer_id} />
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :error_path, :string, required: true
  attr :occurrence_id, :integer, required: true

  defp step(%{occurrence_id: nil} = assigns) do
    ~H"""
    <button class="btn btn--sm" type="button" disabled>{@label}</button>
    """
  end

  defp step(assigns) do
    ~H"""
    <.link class="btn btn--sm" patch={"#{@error_path}?#{URI.encode_query(occurrence: @occurrence_id)}"}>
      {@label}
    </.link>
    """
  end

  attr :occurrence, Occurrence, required: true

  defp occurrence(%{occurrence: %Occurrence{context: context} = occurrence} = assigns) do
    assigns =
      assign(assigns,
        frames: occurrence.stacktrace,
        request: request_rows(Map.get(context, "request", %{})),
        metadata: metadata_rows(Map.get(context, "metadata", %{})),
        runtime: runtime_rows(Map.get(context, "runtime", %{}), occurrence.release)
      )

    ~H"""
    <section :if={@frames != []} class="panel">
      <div class="panel__head">
        <h2 class="section-title">Stack trace</h2>
        <span :if={Enum.any?(@frames, &application_frame?/1)} class="muted" style="font-size:13px">
          The teal edge marks frames in your code
        </span>
      </div>
      <div>
        <details
          :for={frame <- @frames}
          class={["frame", frame_style(frame)]}
          open={application_frame?(frame)}
        >
          <summary>
            <span class="frame__fn">{frame_function(frame)}</span>
            <span :if={frame_location(frame)} class="frame__loc">{frame_location(frame)}</span>
          </summary>
        </details>
      </div>
    </section>
    <.kv_panel title="Request" rows={@request} />
    <.kv_panel title="Logger metadata" rows={@metadata} />
    <.kv_panel title="Runtime" rows={@runtime} />
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true

  defp kv_panel(assigns) do
    ~H"""
    <section :if={@rows != []} class="panel">
      <div class="panel__head">
        <h2 class="section-title">{@title}</h2>
      </div>
      <div class="panel__body">
        <dl class="kv">
          <%= for row <- @rows do %>
            <dt>{row.label}</dt>
            <dd><code>{row.value}</code></dd>
          <% end %>
        </dl>
      </div>
    </section>
    """
  end

  defp back_to_list(%{assigns: %{dashboard_path: dashboard_path}} = socket) do
    socket
    |> put_flash(:error, "That error doesn't exist. It may have been deleted.")
    |> push_navigate(to: dashboard_path)
  end

  defp request_rows(request) when is_map(request) do
    method_and_path =
      [request["method"], request["path"]]
      |> Enum.reject(&blank?/1)
      |> Enum.map_join(" ", &as_text/1)

    [
      %{label: "Method and path", value: method_and_path},
      %{label: "Params", value: request["params"]},
      %{label: "Headers", value: request["headers"]}
    ]
    |> Enum.reject(&blank?(&1.value))
    |> Enum.map(&%{&1 | value: as_text(&1.value)})
  end

  defp request_rows(_request), do: []

  defp metadata_rows(metadata) when is_map(metadata) do
    metadata
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> %{label: key, value: as_text(value)} end)
  end

  defp metadata_rows(_metadata), do: []

  defp runtime_rows(runtime, release) when is_map(runtime) do
    [%{label: "Node", value: runtime["node"]}, %{label: "Release", value: release}]
    |> Enum.reject(&blank?(&1.value))
    |> Enum.map(&%{&1 | value: as_text(&1.value)})
  end

  defp runtime_rows(_runtime, release), do: runtime_rows(%{}, release)

  defp frame_function(%{"module" => module, "function" => function, "arity" => arity}),
    do: "#{module}.#{function}/#{arity}"

  defp frame_style(frame) do
    if application_frame?(frame), do: "frame--app", else: "frame--dep"
  end

  defp application_frame?(frame), do: Map.get(frame, "application") == true

  defp frame_location(%{"file" => file, "line" => line}) when is_binary(file) and is_integer(line), do: "#{file}:#{line}"
  defp frame_location(%{"file" => file}) when is_binary(file), do: file
  defp frame_location(_frame), do: nil

  defp blank?(value), do: value in [nil, "", %{}, []]

  defp as_text(value) when is_binary(value), do: value
  defp as_text(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)

  defp status_flag(status), do: Map.fetch!(@status_flags, status)

  defp status_actions(status), do: Map.fetch!(@status_actions, status)
end
