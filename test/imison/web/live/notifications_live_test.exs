defmodule Imison.Web.NotificationsLiveTest do
  use Imison.ConnCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers
  import Swoosh.TestAssertions

  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Notifications
  alias Imison.Notifications.Channel
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.ChannelSetting
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Message
  alias Imison.Notifications.Rule
  alias Imison.Test.Dashboard
  alias Imison.Test.Mailer
  alias Imison.Test.PagerChannel
  alias Imison.Test.Repo

  defmodule FailingMailer do
    @moduledoc false

    def deliver(_email, _config), do: {:error, :smtp_unavailable}
  end

  defmodule RaisingMailer do
    @moduledoc false

    def deliver(_email, _config), do: raise("SMTP connection refused")
  end

  defmodule BareChannel do
    @moduledoc false

    @behaviour Channel

    @impl Channel
    def type, do: "bare"

    @impl Channel
    def validate_config(_channel_config), do: :ok

    @impl Channel
    def deliver(_message, _channel_config, _conf), do: :ok
  end

  test "following Notifications in the top bar opens the notifications screen" do
    start_mailing_imison()
    conn = sign_in("/errors", "admin", "secret")
    {:ok, list, _html} = live(conn, "/errors")

    {:ok, view, _html} =
      list
      |> element(".nav .nav__link", "Notifications")
      |> render_click()
      |> follow_redirect(conn, "/errors/notifications")

    assert has_element?(view, "h1.page__title", "Notifications")
    assert has_element?(view, ".nav .nav__link[aria-current=page]", "Notifications")
    refute has_element?(view, ".nav .nav__link[aria-current=page]", "Errors")
  end

  test "an error's detail page links to the notifications screen in the top bar" do
    start_mailing_imison()
    error = record_error()

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".nav .nav__link[href='/errors/notifications']", "Notifications")
    assert has_element?(view, ".nav .nav__link[aria-current=page]", "Errors")
  end

  test "the screen shows the email channel's stored recipients, the mailer and sender, and the four rules" do
    start_mailing_imison()
    put_email_channel(["ops@example.com", "kasia@example.com"])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert has_element?(view, ".channel .section-title", "Email")
    assert has_element?(view, "textarea[name='config[recipients]']", "ops@example.com, kasia@example.com")
    assert has_element?(view, ".channel .rule__hint", "Sends with Imison.Test.Mailer as errors@example.com")
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='A new error appears']")
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='A resolved error comes back']")
    assert has_element?(view, ".rule input[type=checkbox][aria-label='An error keeps happening']")
    refute has_element?(view, ".rule input[type=checkbox][checked][aria-label='An error keeps happening']")
    assert has_element?(view, ".rule .rule__hint", "At most one reminder per error per hour.")
    refute has_element?(view, ".rule input[type=checkbox][checked][aria-label='Daily summary']")
    assert has_element?(view, ".rule .rule__hint", "One summary at 08:00 UTC with yesterday's counts.")
    assert rule_count(view) == 4
  end

  test "turning on Daily summary and saving stores the digest rule enabled" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#rules-settings", %{"rules" => %{"digest" => "true"}}) |> render_submit()

    assert stored_rule(:digest).enabled
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='Daily summary']")
  end

  test "turning on An error keeps happening and saving stores the still happening rule enabled" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#rules-settings", %{"rules" => %{"still_happening" => "true"}}) |> render_submit()

    assert stored_rule(:still_happening).enabled
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='An error keeps happening']")
  end

  test "a rule stored as disabled shows its switch off" do
    start_mailing_imison()
    {:ok, _rule} = Notifications.put_rule(Imison.config(Dashboard), :regression, false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='A new error appears']")
    refute has_element?(view, ".rule input[type=checkbox][checked][aria-label='A resolved error comes back']")
  end

  test "without a mailer or from address the screen says how to set them" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert has_element?(view, ".channel .rule__hint", "Set the mailer and from options")
  end

  test "saving the email panel turned on stores the email channel enabled with the recipients" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"enabled" => "true", "config" => %{"recipients" => "a@example.com, b@example.com"}})
    |> render_submit()

    assert %ChannelSetting{enabled: true, config: %{"recipients" => ["a@example.com", "b@example.com"]}} =
             stored_email_channel()

    assert has_element?(view, ".flash--info", "Email settings saved.")
    assert has_element?(view, "#email-channel .flag--on", "On")
  end

  test "saving the rules stores each rule's switch" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#rules-settings", %{"rules" => %{"new" => "true", "regression" => "false"}})
    |> render_submit()

    assert stored_rule(:new).enabled
    refute stored_rule(:regression).enabled
    assert has_element?(view, ".flash--info", "Rules saved.")
  end

  test "saving reads recipients separated by commas or new lines, ignoring blanks and repeats" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"config" => %{"recipients" => " a@example.com,\nb@example.com\n\n, a@example.com "}})
    |> render_submit()

    assert %ChannelSetting{config: %{"recipients" => ["a@example.com", "b@example.com"]}} = stored_email_channel()
  end

  test "saving an invalid address stores nothing and shows which address is invalid" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"enabled" => "true", "config" => %{"recipients" => "ok@example.com, not-an-address"}})
    |> render_submit()

    assert stored_email_channel() == nil
    assert has_element?(view, "#email-recipients-errors", "not-an-address is not an email address")
    refute has_element?(view, "#email-recipients-errors", "ok@example.com")
    refute has_element?(view, ".flash--info")
  end

  test "saving without recipients stores nothing and asks for one" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"config" => %{"recipients" => " "}}) |> render_submit()

    assert stored_email_channel() == nil
    assert has_element?(view, "#email-recipients-errors", "must list at least one email address")
  end

  test "sending a test email delivers one test email to the form's recipients" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"config" => %{"recipients" => "a@example.com, b@example.com"}}) |> render_change()
    send_test(view, "email")

    assert_email_sent(
      from: {"", "errors@example.com"},
      to: [{"", "a@example.com"}, {"", "b@example.com"}],
      subject: "[Imison] Test email"
    )

    refute_email_sent()
    assert has_element?(view, ".flash--info", "Test sent through Email.")
    assert stored_email_channel() == nil
  end

  test "sending a test email with a saved email channel records no delivery" do
    set_swoosh_global()
    start_mailing_imison()
    put_email_channel(["ops@example.com"])
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    send_test(view, "email")

    assert_email_sent(subject: "[Imison] Test email", to: [{"", "ops@example.com"}])
    assert Repo.all(Delivery) == []
  end

  test "the test email says that delivery works" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"config" => %{"recipients" => "a@example.com"}}) |> render_change()
    send_test(view, "email")

    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ "Email delivery from Imison works"
  end

  test "sending a test email to an invalid address sends nothing and shows which address is invalid" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"config" => %{"recipients" => "not-an-address"}}) |> render_change()
    send_test(view, "email")

    refute_email_sent()
    assert has_element?(view, "#email-recipients-errors", "not-an-address is not an email address")
  end

  test "a mailer that returns an error shows it and logs the failure" do
    start_mailing_imison(mailer: FailingMailer)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"config" => %{"recipients" => "a@example.com"}}) |> render_change()

    log = capture_log(fn -> send_test(view, "email") end)

    assert has_element?(view, ".flash--error", "Couldn't send the test through Email: :smtp_unavailable")
    assert log =~ "Imison failed to deliver a notification"
  end

  test "a mailer that raises shows the error and the screen keeps working" do
    start_mailing_imison(mailer: RaisingMailer)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"config" => %{"recipients" => "a@example.com"}}) |> render_change()

    log = capture_log(fn -> send_test(view, "email") end)

    assert has_element?(view, ".flash--error", "Couldn't send the test through Email")
    assert has_element?(view, ".flash--error", "SMTP connection refused")
    assert log =~ "SMTP connection refused"
    assert has_element?(view, "#email-settings button", "Send test")
  end

  test "without a mailer the test email fails with an error message" do
    start_imison(name: Dashboard, enabled: false, from: "errors@example.com")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"config" => %{"recipients" => "a@example.com"}}) |> render_change()

    capture_log(fn -> send_test(view, "email") end)

    assert has_element?(view, ".flash--error", "Couldn't send the test through Email: :mailer_not_configured")
  end

  test "without any channel the screen says how to enable email, with no form" do
    start_imison(name: Dashboard, enabled: false, channels: [])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert has_element?(view, ".channel .empty__title", "Email isn't available")
    assert has_element?(view, ".channel .empty__text", "swoosh")
    refute has_element?(view, "#email-settings")
    refute has_element?(view, "#rules-settings")
    refute has_element?(view, "button", "Send test")
  end

  test "the screen shows one panel per channel, titled by its label or else its type, each with an on/off switch and its fields" do
    start_mailing_imison(channels: [Email, PagerChannel, BareChannel])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert panel_titles(view) == ["Email", "Pager", "bare"]
    assert has_element?(view, "#email-settings input[type=checkbox][aria-label='Send notifications through Email']")
    assert has_element?(view, "#pager-settings input[type=checkbox][aria-label='Send notifications through Pager']")
    assert has_element?(view, "#bare-settings input[type=checkbox][aria-label='Send notifications through bare']")
    assert has_element?(view, "#email-settings textarea[name='config[recipients]']")
    assert has_element?(view, "#pager-settings label[for=pager-service_url]", "Service URL")
    assert has_element?(view, "#pager-settings input[type=url][name='config[service_url]']")
    assert has_element?(view, "#pager-settings .field__hint", "Where the pager service takes alerts.")
    assert has_element?(view, "#pager-settings label[for=pager-token]", "API token")
    assert has_element?(view, "#pager-settings input[type=password][name='config[token]']")
    assert has_element?(view, "#pager-settings button", "Send test")
    assert has_element?(view, "#pager-settings button[type=submit]", "Save changes")
  end

  test "filling a channel's fields, turning it on and saving stores it enabled with those settings" do
    start_mailing_imison(channels: [Email, PagerChannel])
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#pager-settings", %{
      "enabled" => "true",
      "config" => %{"service_url" => " https://pager.example.com/alerts ", "token" => "pager-token-1"}
    })
    |> render_submit()

    assert %ChannelSetting{
             enabled: true,
             config: %{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"}
           } = stored_channel(PagerChannel)

    assert stored_email_channel() == nil
    assert has_element?(view, ".flash--info", "Pager settings saved.")
    assert has_element?(view, "#pager-channel .flag--on", "On")
  end

  test "turning a stored channel off and saving stores it disabled with its settings" do
    start_mailing_imison(channels: [PagerChannel])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#pager-settings", %{"enabled" => "false"}) |> render_submit()

    assert %ChannelSetting{
             enabled: false,
             config: %{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"}
           } = stored_channel(PagerChannel)

    assert has_element?(view, "#pager-channel .flag--off", "Off")
  end

  test "saving a channel with invalid fields shows each field's error under it and stores nothing" do
    start_mailing_imison(channels: [PagerChannel])
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#pager-settings", %{"enabled" => "true", "config" => %{"service_url" => "ftp://pager.example.com"}})
    |> render_submit()

    assert stored_channel(PagerChannel) == nil
    assert has_element?(view, "#pager-service_url-errors", "must start with https://")
    assert has_element?(view, "#pager-token-errors", "can't be blank")
    refute has_element?(view, ".flash--info")
  end

  test "a stored secret isn't shown on the screen, only that it is set" do
    start_mailing_imison(channels: [PagerChannel])
    secret_token = "pager-token-#{System.unique_integer([:positive])}"
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => secret_token})

    {:ok, view, html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    refute html =~ secret_token
    refute render(view) =~ secret_token
    assert has_element?(view, "#pager-settings .field__hint", "Set — leave blank to keep.")

    assert has_element?(
             view,
             "#pager-settings input[name='config[service_url]'][value='https://pager.example.com/alerts']"
           )
  end

  test "saving with a stored secret left blank keeps the stored secret" do
    start_mailing_imison(channels: [PagerChannel])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#pager-settings", %{"config" => %{"service_url" => "https://pager.example.com/v2", "token" => ""}})
    |> render_submit()

    assert %ChannelSetting{config: %{"service_url" => "https://pager.example.com/v2", "token" => "pager-token-1"}} =
             stored_channel(PagerChannel)
  end

  test "saving a new secret replaces the stored one without showing it" do
    start_mailing_imison(channels: [PagerChannel])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#pager-settings", %{"config" => %{"token" => "pager-token-2"}}) |> render_submit()

    assert %ChannelSetting{config: %{"token" => "pager-token-2"}} = stored_channel(PagerChannel)
    refute render(view) =~ "pager-token-2"
  end

  test "saving keeps stored settings the channel's fields don't list" do
    start_mailing_imison(channels: [PagerChannel])

    put_pager_channel(%{
      "service_url" => "https://pager.example.com/alerts",
      "token" => "pager-token-1",
      "escalation" => "night-shift"
    })

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#pager-settings", %{"config" => %{"service_url" => "https://pager.example.com/v2"}}) |> render_submit()

    assert %ChannelSetting{config: %{"escalation" => "night-shift"}} = stored_channel(PagerChannel)
  end

  test "Send test on a channel's panel delivers a test message through that channel alone and names it" do
    set_swoosh_global()
    start_mailing_imison(channels: [Email, PagerChannel])
    put_email_channel(["ops@example.com"])
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#pager-settings", %{"config" => %{"service_url" => "https://pager.example.com/alerts", "token" => "t1"}})
    |> render_change()

    send_test(view, "pager")

    assert_received {:paged, %Message{trigger: :test},
                     %{"service_url" => "https://pager.example.com/alerts", "token" => "t1"}}

    refute_email_sent()
    assert has_element?(view, ".flash--info", "Test sent through Pager.")
    assert stored_channel(PagerChannel) == nil
  end

  test "Send test with a stored secret left blank sends with the stored secret" do
    start_mailing_imison(channels: [PagerChannel])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    send_test(view, "pager")

    assert_received {:paged, %Message{trigger: :test}, %{"token" => "pager-token-1"}}
  end

  test "Send test with invalid fields sends nothing and shows each field's error" do
    start_mailing_imison(channels: [PagerChannel])
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    send_test(view, "pager")

    refute_received {:paged, _message, _channel_config}
    assert has_element?(view, "#pager-service_url-errors", "must start with https://")
    assert has_element?(view, "#pager-token-errors", "can't be blank")
  end

  test "a host's channel saved on the screen receives a new error captured afterwards" do
    start_imison(name: Dashboard, channels: [PagerChannel])
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#pager-settings", %{
      "enabled" => "true",
      "config" => %{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"}
    })
    |> render_submit()

    message = capture_new_error()
    wait_for_worker(Dashboard)

    assert_received {:paged, %Message{trigger: :new, message: ^message}, %{"token" => "pager-token-1"}}
  end

  test "a rule switched off on the screen sends nothing through any channel" do
    set_swoosh_global()
    start_mailing_imison(enabled: true, channels: [Email, PagerChannel])
    put_email_channel(["ops@example.com"])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#rules-settings", %{"rules" => %{"new" => "false"}}) |> render_submit()
    capture_new_error()
    wait_for_worker(Dashboard)

    refute_email_sent()
    refute_received {:paged, _message, _channel_config}
  end

  test "a rule switched on on the screen sends through every channel that's on" do
    set_swoosh_global()
    start_mailing_imison(enabled: true, channels: [Email, PagerChannel])
    put_email_channel(["ops@example.com"])
    put_pager_channel(%{"service_url" => "https://pager.example.com/alerts", "token" => "pager-token-1"})
    Process.register(self(), PagerChannel)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#rules-settings", %{"rules" => %{"new" => "true"}}) |> render_submit()
    message = capture_new_error()
    wait_for_worker(Dashboard)

    assert_email_sent(to: [{"", "ops@example.com"}])
    assert_received {:paged, %Message{trigger: :new, message: ^message}, _channel_config}
  end

  test "a visitor without a session is redirected from the notifications screen to the login page" do
    start_mailing_imison()

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(browser_conn(), "/errors/notifications")
  end

  defp start_mailing_imison(opts \\ []) do
    [name: Dashboard, enabled: false, mailer: Mailer, from: "errors@example.com"]
    |> Keyword.merge(opts)
    |> start_imison()
  end

  defp put_email_channel(recipients) do
    {:ok, channel} =
      Notifications.put_channel(Imison.config(Dashboard), Email.type(), %{
        enabled: true,
        config: %{"recipients" => recipients}
      })

    channel
  end

  defp put_pager_channel(channel_config) do
    {:ok, channel} =
      Notifications.put_channel(Imison.config(Dashboard), PagerChannel.type(), %{enabled: true, config: channel_config})

    channel
  end

  defp send_test(view, type) do
    view |> element("##{type}-settings button", "Send test") |> render_click()
  end

  defp capture_new_error do
    {exception, stacktrace} = raised(unique_message())
    event = Capture.event(%{kind: :error, reason: exception, stacktrace: stacktrace}, %{})
    Capture.capture(Dashboard, %{event | kind: "Imison.NotificationsLiveTestError#{System.unique_integer([:positive])}"})
    event.message
  end

  defp panel_titles(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".channel .section-title")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp record_error do
    {:ok, error} =
      Errors.record(Imison.config(Dashboard), %{
        kind: "RuntimeError",
        message: unique_message(),
        stacktrace: [],
        context: %{},
        occurred_at: DateTime.utc_now()
      })

    error
  end

  defp rule_count(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#rules-settings .rule input[type=checkbox]")
    |> Enum.count()
  end

  defp stored_email_channel, do: stored_channel(Email)

  defp stored_channel(channel_module), do: Repo.get_by(ChannelSetting, type: channel_module.type())

  defp stored_rule(trigger), do: Repo.get_by(Rule, trigger: trigger)
end
