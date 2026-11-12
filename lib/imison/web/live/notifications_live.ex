defmodule Imison.Web.NotificationsLive do
  @moduledoc """
  The notifications screen (`docs/design/notifications.html`): the email
  channel's recipients, the mailer and sender from the instance's config,
  and a switch for each rule that sends email today (a new error, a resolved
  error that comes back).

  Saving stores the channel, enabled, with the recipients and every switch's
  rule, all or nothing; recipients are separated by commas or new lines and
  each must be an email address. "Send test email" sends the test message to
  the recipients in the form, saved or not, and shows whether the mailer
  accepted it.

  Without the email channel in the `channels` option (the host doesn't
  depend on Swoosh) the screen says how to enable it instead.
  """

  use Phoenix.LiveView

  alias Imison.Notifications
  alias Imison.Notifications.ChannelSetting
  alias Imison.Web.Layouts

  @email_channel Imison.Notifications.Channels.Email
  @rules [
    %{trigger: :new, title: "A new error appears", hint: "The first time an error is seen."},
    %{trigger: :regression, title: "A resolved error comes back", hint: "You marked it resolved and it happened again."}
  ]

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    conf = Imison.config(imison_name)

    {:ok,
     socket
     |> assign(
       conf: conf,
       dashboard_path: dashboard_path,
       page_title: "Notifications",
       email_channel: email_channel(conf),
       recipient_errors: []
     )
     |> load_settings()}
  end

  @impl Phoenix.LiveView
  def handle_event("change", params, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("save", params, %{assigns: %{conf: conf, email_channel: email_channel}} = socket) do
    socket = assign_form(socket, params)
    settings = %{config: recipients_config(socket.assigns.recipients), rules: socket.assigns.rules}

    case Notifications.put_channel_and_rules(conf, email_channel, settings) do
      {:ok, %ChannelSetting{} = channel} ->
        {:noreply,
         socket
         |> assign(channel_on: channel.enabled, recipients: recipients_text(channel), recipient_errors: [])
         |> put_flash(:info, "Email settings saved.")}

      {:error, {:invalid_config, reasons}} ->
        {:noreply, show_invalid_recipients(socket, reasons)}
    end
  end

  def handle_event("send_test", _params, %{assigns: %{conf: conf, email_channel: email_channel}} = socket) do
    recipients_config = recipients_config(socket.assigns.recipients)

    case Notifications.send_test(conf, email_channel, recipients_config) do
      :ok ->
        {:noreply,
         socket
         |> assign(recipient_errors: [])
         |> put_flash(:info, "Test email sent to #{Enum.join(recipients_config["recipients"], ", ")}.")}

      {:error, {:invalid_config, reasons}} ->
        {:noreply, show_invalid_recipients(socket, reasons)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(recipient_errors: [])
         |> put_flash(:error, "Couldn't send the test email: #{describe_failure(reason)}")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app dashboard_path={@dashboard_path} current={:notifications} flash={@flash}>
      <div class="page__head">
        <div>
          <h1 class="page__title">Notifications</h1>
          <p class="page__lede">Choose where Imison tells you about errors, and which errors are worth an alert.</p>
        </div>
      </div>
      <.email_panel
        :if={@email_channel}
        conf={@conf}
        channel_on={@channel_on}
        recipients={@recipients}
        recipient_errors={@recipient_errors}
        rules={@rules}
      />
      <.email_unavailable :if={!@email_channel} />
    </Layouts.app>
    """
  end

  attr :conf, Imison.Config, required: true
  attr :channel_on, :boolean, required: true
  attr :recipients, :string, required: true
  attr :recipient_errors, :list, required: true
  attr :rules, :map, required: true

  defp email_panel(assigns) do
    assigns = assign(assigns, rule_definitions: @rules)

    ~H"""
    <section class="panel channel">
      <div class="panel__head">
        <.email_title hint={mailer_hint(@conf)} />
        <span :if={@channel_on} class="flag flag--on">On</span>
        <span :if={!@channel_on} class="flag flag--off">Off</span>
      </div>
      <form id="email-settings" phx-change="change" phx-submit="save">
        <div class="panel__body form-grid">
          <div>
            <div class="field">
              <label class="field__label" for="recipients">Send to</label>
              <textarea
                class="textarea"
                id="recipients"
                name="recipients"
                aria-invalid={to_string(@recipient_errors != [])}
                aria-describedby={recipients_described_by(@recipient_errors)}
              >{@recipients}</textarea>
              <span class="field__hint" id="recipients-hint">Separate addresses with commas or new lines.</span>
              <ul :if={@recipient_errors != []} id="recipients-errors" class="field__error">
                <li :for={recipient_error <- @recipient_errors}>{recipient_error}</li>
              </ul>
            </div>
            <div class="field">
              <span class="field__label">Mailer</span>
              <.mailer_config conf={@conf} />
            </div>
          </div>
          <div>
            <p class="field__label" style="margin-bottom:12px">Send an email when</p>
            <ul>
              <li :for={rule <- @rule_definitions} class="rule">
                <input type="hidden" name={"rules[#{rule.trigger}]"} value="false" />
                <label class="switch">
                  <input
                    type="checkbox"
                    name={"rules[#{rule.trigger}]"}
                    value="true"
                    checked={@rules[rule.trigger]}
                    aria-label={rule.title}
                  /><span class="switch__track"></span>
                </label>
                <div class="rule__text">
                  <p class="rule__title">{rule.title}</p>
                  <p class="rule__hint">{rule.hint}</p>
                </div>
              </li>
            </ul>
          </div>
        </div>
        <div class="panel__foot">
          <button class="btn" type="button" phx-click="send_test">Send test email</button>
          <button class="btn btn--primary" type="submit">Save changes</button>
        </div>
      </form>
    </section>
    """
  end

  attr :conf, Imison.Config, required: true

  defp mailer_config(%{conf: %{mailer: mailer, from: from}} = assigns) when not is_nil(mailer) and not is_nil(from) do
    ~H"""
    <span class="field__hint">
      Email goes out through the mailer and sender address in this app’s Imison config:
      <code>mailer: {inspect(@conf.mailer)}, from: {inspect(@conf.from)}</code>.
    </span>
    """
  end

  defp mailer_config(assigns) do
    ~H"""
    <span class="field__hint">
      Email goes out through your app’s Swoosh mailer. Add both to this app’s Imison config:
      <code>mailer: MyApp.Mailer, from: "errors@example.com"</code>.
    </span>
    """
  end

  defp email_unavailable(assigns) do
    ~H"""
    <section class="panel channel">
      <div class="panel__head">
        <.email_title hint="Email errors to your team." />
        <span class="flag flag--off">Unavailable</span>
      </div>
      <div class="empty">
        <h2 class="empty__title">Email isn't available</h2>
        <p class="empty__text">
          Add <code>{"{:swoosh, \"~> 1.29\"}"}</code>
          to your app’s dependencies and keep <code>Imison.Notifications.Channels.Email</code>
          in the <code>channels</code>
          option, then set <code>mailer</code>
          and <code>from</code>.
        </p>
      </div>
    </section>
    """
  end

  attr :hint, :string, required: true

  defp email_title(assigns) do
    ~H"""
    <div class="channel__title">
      <span class="channel__icon">
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 7 9 6 9-6" />
        </svg>
      </span>
      <div>
        <h2 class="section-title">Email</h2>
        <p class="rule__hint">{@hint}</p>
      </div>
    </div>
    """
  end

  defp email_channel(%{channels: channels}) do
    if @email_channel in channels, do: @email_channel
  end

  defp load_settings(%{assigns: %{email_channel: nil}} = socket), do: socket

  defp load_settings(%{assigns: %{conf: conf, email_channel: email_channel}} = socket) do
    channel = Notifications.channel_setting(conf, email_channel.type())

    assign(socket,
      channel_on: match?(%ChannelSetting{enabled: true}, channel),
      recipients: recipients_text(channel),
      rules: Map.new(@rules, &{&1.trigger, Notifications.rule_enabled?(conf, &1.trigger)})
    )
  end

  defp assign_form(%{assigns: %{rules: rules}} = socket, params) do
    assign(socket,
      recipients: recipients_param(params, socket.assigns.recipients),
      rules: Map.new(rules, fn {trigger, enabled} -> {trigger, rule_switch(params, trigger, enabled)} end)
    )
  end

  defp rule_switch(%{"rules" => %{} = switches}, trigger, enabled) do
    case Map.get(switches, Atom.to_string(trigger)) do
      "true" -> true
      "false" -> false
      _missing -> enabled
    end
  end

  defp rule_switch(_params, _trigger, enabled), do: enabled

  defp show_invalid_recipients(socket, reasons) do
    socket
    |> assign(recipient_errors: Keyword.get_values(reasons, :recipients))
    |> clear_flash()
  end

  defp recipients_described_by([]), do: "recipients-hint"
  defp recipients_described_by(_recipient_errors), do: "recipients-hint recipients-errors"

  defp recipients_param(%{"recipients" => recipients}, _recipients) when is_binary(recipients), do: recipients
  defp recipients_param(_params, recipients), do: recipients

  defp recipients_config(recipients) do
    %{
      "recipients" =>
        recipients
        |> String.split([",", "\n"])
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
    }
  end

  defp recipients_text(%ChannelSetting{config: %{"recipients" => recipients}}) when is_list(recipients),
    do: Enum.join(recipients, ", ")

  defp recipients_text(_channel), do: ""

  defp mailer_hint(%{mailer: mailer, from: from}) when not is_nil(mailer) and not is_nil(from),
    do: "Sends with #{inspect(mailer)} as #{from}"

  defp mailer_hint(_conf), do: "Set the mailer and from options to send email."

  defp describe_failure(reason) when is_exception(reason), do: Exception.message(reason)
  defp describe_failure(reason), do: inspect(reason)
end
