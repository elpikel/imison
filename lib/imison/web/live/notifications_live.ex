defmodule Imison.Web.NotificationsLive do
  @moduledoc """
  The notifications screen (`docs/design/notifications.html`): one panel per
  module in the `channels` option, then the rules, which apply to every
  channel that's on (a new error, a resolved error that comes back, an error
  that keeps happening, the daily summary).

  A channel's panel is titled by its `label/0` (else its `type/0`), shows its
  `describe/1` line, an On/Off flag for the stored row, its `config_fields/0`
  as inputs and a switch that turns it on or off. Saving stores the switch
  and the fields, after the channel's `validate_config/1`; its errors are
  listed under the fields and nothing is stored. "Send test" sends the test
  message through that channel alone with the form's values, saved or not,
  and names the channel in the flash. A secret field is never rendered back:
  it says a value is set, and leaving it blank keeps the stored value, on
  save and on test; ticking its Remove box clears the stored value instead
  (a new value typed in wins). Recipients are separated by commas or new lines.

  Without any channel in the `channels` option (the host doesn't depend on
  Swoosh) the screen says how to enable email instead.
  """

  use Phoenix.LiveView

  alias Imison.Notifications
  alias Imison.Notifications.Channel
  alias Imison.Notifications.ChannelSetting
  alias Imison.Web.Layouts

  @rules [
    %{trigger: :new, title: "A new error appears", hint: "The first time an error is seen."},
    %{trigger: :regression, title: "A resolved error comes back", hint: "You marked it resolved and it happened again."},
    %{trigger: :still_happening, title: "An error keeps happening", hint: "At most one reminder per error per hour."},
    %{trigger: :digest, title: "Daily summary", hint: "One summary at 08:00 UTC with yesterday's counts."}
  ]

  @impl Phoenix.LiveView
  def mount(_params, %{"imison_name" => imison_name, "dashboard_path" => dashboard_path}, socket) do
    conf = Imison.config(imison_name)

    {:ok,
     assign(socket,
       conf: conf,
       dashboard_path: dashboard_path,
       page_title: "Notifications",
       panels: Enum.map(conf.channels, &load_panel(conf, &1)),
       rules: Map.new(@rules, &{&1.trigger, Notifications.rule_enabled?(conf, &1.trigger)})
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("change_channel", %{"channel" => type} = params, socket) do
    {:noreply, update_panel(socket, type, &put_draft(&1, params))}
  end

  def handle_event("save_channel", %{"channel" => type} = params, %{assigns: %{conf: conf}} = socket) do
    socket = update_panel(socket, type, &put_draft(&1, params))
    panel = find_panel(socket, type)
    settings = Map.put(submission(panel), :enabled, panel.enabled)

    case Notifications.put_channel_settings(conf, panel.module, settings) do
      {:ok, %ChannelSetting{} = setting} ->
        {:noreply,
         socket
         |> update_panel(type, &show_stored(&1, setting))
         |> put_flash(:info, "#{panel.label} settings saved.")}

      {:error, {:invalid_config, reasons}} ->
        {:noreply, show_invalid_config(socket, type, reasons)}
    end
  end

  def handle_event("send_test", %{"channel" => type}, %{assigns: %{conf: conf}} = socket) do
    panel = find_panel(socket, type)

    case Notifications.send_test(conf, panel.module, submission(panel)) do
      :ok ->
        {:noreply,
         socket
         |> update_panel(type, &Map.put(&1, :errors, []))
         |> put_flash(:info, "Test sent through #{panel.label}.")}

      {:error, {:invalid_config, reasons}} ->
        {:noreply, show_invalid_config(socket, type, reasons)}

      {:error, reason} ->
        {:noreply,
         socket
         |> update_panel(type, &Map.put(&1, :errors, []))
         |> put_flash(:error, "Couldn't send the test through #{panel.label}: #{describe_failure(reason)}")}
    end
  end

  def handle_event("change_rules", params, socket) do
    {:noreply, assign_rules(socket, params)}
  end

  def handle_event("save_rules", params, %{assigns: %{conf: conf}} = socket) do
    socket = assign_rules(socket, params)
    {:ok, _rules} = Notifications.put_rules(conf, socket.assigns.rules)
    {:noreply, put_flash(socket, :info, "Rules saved.")}
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
      <.channel_panel :for={panel <- @panels} panel={panel} />
      <.rules_panel :if={@panels != []} rules={@rules} />
      <.no_channels :if={@panels == []} />
    </Layouts.app>
    """
  end

  attr :panel, :map, required: true

  defp channel_panel(assigns) do
    assigns = assign(assigns, other_errors: errors_outside_fields(assigns.panel))

    ~H"""
    <section class="panel channel" id={"#{@panel.type}-channel"}>
      <div class="panel__head">
        <.channel_title type={@panel.type} label={@panel.label} description={@panel.description} />
        <span :if={@panel.stored_enabled} class="flag flag--on">On</span>
        <span :if={!@panel.stored_enabled} class="flag flag--off">Off</span>
      </div>
      <form id={"#{@panel.type}-settings"} phx-change="change_channel" phx-submit="save_channel">
        <input type="hidden" name="channel" value={@panel.type} />
        <div class="panel__body form-grid">
          <div>
            <.config_field :for={field <- @panel.fields} field={field} panel={@panel} />
            <p :if={@panel.fields == []} class="field__hint">This channel has no settings.</p>
            <ul :if={@other_errors != []} id={"#{@panel.type}-errors"} class="field__error">
              <li :for={other_error <- @other_errors}>{other_error}</li>
            </ul>
          </div>
          <ul>
            <li class="rule">
              <input type="hidden" name="enabled" value="false" />
              <label class="switch">
                <input
                  type="checkbox"
                  name="enabled"
                  value="true"
                  checked={@panel.enabled}
                  aria-label={"Send notifications through #{@panel.label}"}
                /><span class="switch__track"></span>
              </label>
              <div class="rule__text">
                <p class="rule__title">Send notifications through {@panel.label}</p>
                <p class="rule__hint">Off keeps the settings and sends nothing.</p>
              </div>
            </li>
          </ul>
        </div>
        <div class="panel__foot">
          <button class="btn" type="button" phx-click="send_test" phx-value-channel={@panel.type}>Send test</button>
          <button class="btn btn--primary" type="submit">Save changes</button>
        </div>
      </form>
    </section>
    """
  end

  attr :field, :map, required: true
  attr :panel, :map, required: true

  defp config_field(%{field: field, panel: panel} = assigns) do
    id = "#{panel.type}-#{field.name}"
    errors = field_errors(panel.errors, field.name)
    secret_set = field.type == :secret and field.name in panel.secrets_set
    hint = Map.get(field, :hint)

    assigns =
      assign(assigns,
        id: id,
        name: "config[#{field.name}]",
        value: Map.get(panel.values, field.name, ""),
        errors: errors,
        secret_set: secret_set,
        removed: field.name in panel.removed_secrets,
        hint: hint,
        described_by: described_by(id, %{secret_set: secret_set, hint: hint, errors: errors})
      )

    ~H"""
    <div class="field">
      <label class="field__label" for={@id}>{@field.label}</label>
      <textarea
        :if={@field.type == :recipients}
        class="textarea"
        id={@id}
        name={@name}
        aria-invalid={to_string(@errors != [])}
        aria-describedby={@described_by}
      >{@value}</textarea>
      <input
        :if={@field.type in [:text, :url]}
        class="input"
        type={input_type(@field.type)}
        id={@id}
        name={@name}
        value={@value}
        aria-invalid={to_string(@errors != [])}
        aria-describedby={@described_by}
      />
      <input
        :if={@field.type == :secret}
        class="input"
        type="password"
        autocomplete="new-password"
        id={@id}
        name={@name}
        aria-invalid={to_string(@errors != [])}
        aria-describedby={@described_by}
      />
      <span :if={@secret_set} class="field__hint" id={"#{@id}-set"}>Set — leave blank to keep.</span>
      <label :if={@secret_set} class="field__hint">
        <input type="hidden" name={"remove[#{@field.name}]"} value="false" />
        <input
          class="checkbox"
          type="checkbox"
          name={"remove[#{@field.name}]"}
          value="true"
          checked={@removed}
          aria-label={"Remove the stored #{@field.label}"}
        /> Remove
      </label>
      <span :if={@hint} class="field__hint" id={"#{@id}-hint"}>{@hint}</span>
      <ul :if={@errors != []} id={"#{@id}-errors"} class="field__error">
        <li :for={field_error <- @errors}>{field_error}</li>
      </ul>
    </div>
    """
  end

  attr :rules, :map, required: true

  defp rules_panel(assigns) do
    assigns = assign(assigns, rule_definitions: @rules)

    ~H"""
    <section class="panel" id="rules">
      <div class="panel__head">
        <h2 class="section-title">Send a notification when</h2>
      </div>
      <form id="rules-settings" phx-change="change_rules" phx-submit="save_rules">
        <div class="panel__body">
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
        <div class="panel__foot">
          <span class="field__hint">Rules apply to every channel that's on.</span>
          <button class="btn btn--primary" type="submit">Save rules</button>
        </div>
      </form>
    </section>
    """
  end

  defp no_channels(assigns) do
    ~H"""
    <section class="panel channel">
      <div class="panel__head">
        <.channel_title type="email" label="Email" description="Email errors to your team." />
        <span class="flag flag--off">Unavailable</span>
      </div>
      <div class="empty">
        <h2 class="empty__title">Email isn't available</h2>
        <p class="empty__text">
          Add <code>{"{:swoosh, \"~> 1.29\"}"}</code>
          to your app’s dependencies and keep <code>Imison.Notifications.Channels.Email</code>
          in the <code>channels</code>
          option, then set <code>mailer</code>
          and <code>from</code>. Your own channel modules go in <code>channels</code> too.
        </p>
      </div>
    </section>
    """
  end

  attr :type, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, default: nil

  defp channel_title(assigns) do
    ~H"""
    <div class="channel__title">
      <span class="channel__icon"><.channel_icon type={@type} /></span>
      <div>
        <h2 class="section-title">{@label}</h2>
        <p :if={@description} class="rule__hint">{@description}</p>
      </div>
    </div>
    """
  end

  attr :type, :string, required: true

  defp channel_icon(%{type: "email"} = assigns) do
    ~H"""
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
    """
  end

  defp channel_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
    </svg>
    """
  end

  defp load_panel(conf, channel_module) do
    show_stored(
      %{
        module: channel_module,
        type: channel_module.type(),
        label: Channel.label(channel_module),
        description: Channel.describe(channel_module, conf),
        fields: Channel.config_fields(channel_module)
      },
      Notifications.channel_setting(conf, channel_module.type())
    )
  end

  defp show_stored(panel, nil), do: show_stored(panel, %ChannelSetting{enabled: false, config: %{}})

  defp show_stored(panel, %ChannelSetting{enabled: enabled, config: stored_config}) do
    Map.merge(panel, %{
      stored_enabled: enabled,
      enabled: enabled,
      values: Map.new(panel.fields, &{&1.name, shown_value(&1, Map.get(stored_config, &1.name))}),
      secrets_set: for(%{type: :secret, name: name} <- panel.fields, present?(stored_config[name]), do: name),
      removed_secrets: [],
      errors: []
    })
  end

  defp shown_value(%{type: :secret}, _stored_value), do: ""
  defp shown_value(%{type: :recipients}, stored_value) when is_list(stored_value), do: Enum.join(stored_value, ", ")
  defp shown_value(_field, stored_value) when is_binary(stored_value), do: stored_value
  defp shown_value(_field, _stored_value), do: ""

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp put_draft(panel, params) do
    submitted_values = Map.get(params, "config", %{})

    %{
      panel
      | enabled: switch_param(params, panel.enabled),
        values: Map.new(panel.values, fn {name, value} -> {name, text_param(submitted_values, name, value)} end),
        removed_secrets: removed_secrets_param(params, panel)
    }
  end

  defp removed_secrets_param(%{"remove" => %{} = boxes}, %{secrets_set: secrets_set, removed_secrets: removed_secrets}) do
    for name <- secrets_set, removal_ticked?(Map.get(boxes, name), name in removed_secrets), do: name
  end

  defp removed_secrets_param(_params, %{removed_secrets: removed_secrets}), do: removed_secrets

  defp removal_ticked?("true", _ticked), do: true
  defp removal_ticked?("false", _ticked), do: false
  defp removal_ticked?(_missing, ticked), do: ticked

  defp switch_param(%{"enabled" => "true"}, _enabled), do: true
  defp switch_param(%{"enabled" => "false"}, _enabled), do: false
  defp switch_param(_params, enabled), do: enabled

  defp text_param(%{} = submitted_values, name, value) do
    case Map.get(submitted_values, name) do
      submitted_value when is_binary(submitted_value) -> submitted_value
      _missing -> value
    end
  end

  defp text_param(_submitted_values, _name, value), do: value

  defp submission(panel), do: %{config: submitted_config(panel), removed_secrets: panel.removed_secrets}

  defp submitted_config(%{fields: fields, values: values}) do
    Map.new(fields, &{&1.name, submitted_value(&1, Map.get(values, &1.name, ""))})
  end

  defp submitted_value(%{type: :recipients}, text) do
    text
    |> String.split([",", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp submitted_value(_field, text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp show_invalid_config(socket, type, reasons) do
    socket
    |> update_panel(type, &Map.put(&1, :errors, reasons))
    |> clear_flash()
  end

  defp field_errors(errors, name), do: for({key, message} <- errors, to_string(key) == name, do: message)

  defp errors_outside_fields(%{fields: fields, errors: errors}) do
    names = Enum.map(fields, & &1.name)
    for {key, message} <- errors, to_string(key) not in names, do: message
  end

  defp described_by(id, %{secret_set: secret_set, hint: hint, errors: errors}) do
    [secret_set && "#{id}-set", hint && "#{id}-hint", errors != [] && "#{id}-errors"]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp input_type(:url), do: "url"
  defp input_type(:text), do: "text"

  defp find_panel(%{assigns: %{panels: panels}}, type), do: Enum.find(panels, &(&1.type == type))

  defp update_panel(%{assigns: %{panels: panels}} = socket, type, update) do
    assign(socket, panels: Enum.map(panels, &if(&1.type == type, do: update.(&1), else: &1)))
  end

  defp assign_rules(%{assigns: %{rules: rules}} = socket, params) do
    assign(socket, rules: Map.new(rules, fn {trigger, enabled} -> {trigger, rule_switch(params, trigger, enabled)} end))
  end

  defp rule_switch(%{"rules" => %{} = switches}, trigger, enabled) do
    case Map.get(switches, Atom.to_string(trigger)) do
      "true" -> true
      "false" -> false
      _missing -> enabled
    end
  end

  defp rule_switch(_params, _trigger, enabled), do: enabled

  defp describe_failure(reason) when is_exception(reason), do: Exception.message(reason)
  defp describe_failure(reason), do: inspect(reason)
end
