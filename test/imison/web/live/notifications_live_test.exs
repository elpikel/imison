defmodule Imison.Web.NotificationsLiveTest do
  use Imison.ConnCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers
  import Swoosh.TestAssertions

  alias Imison.Errors
  alias Imison.Notifications
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.ChannelSetting
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Rule
  alias Imison.Test.Dashboard
  alias Imison.Test.Mailer
  alias Imison.Test.Repo

  defmodule FailingMailer do
    @moduledoc false

    def deliver(_email, _config), do: {:error, :smtp_unavailable}
  end

  defmodule RaisingMailer do
    @moduledoc false

    def deliver(_email, _config), do: raise("SMTP connection refused")
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
    assert has_element?(view, "textarea[name=recipients]", "ops@example.com, kasia@example.com")
    assert has_element?(view, ".channel .rule__hint", "Sends with Imison.Test.Mailer as errors@example.com")
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='A new error appears']")
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='A resolved error comes back']")
    assert has_element?(view, ".rule input[type=checkbox][aria-label='An error keeps happening']")
    refute has_element?(view, ".rule input[type=checkbox][checked][aria-label='An error keeps happening']")
    assert has_element?(view, ".rule .rule__hint", "At most one reminder per error per hour.")
    refute has_element?(view, ".rule input[type=checkbox][checked][aria-label='Daily summary']")
    assert has_element?(view, ".rule .rule__hint", "One email at 08:00 UTC with yesterday's counts.")
    assert rule_count(view) == 4
  end

  test "turning on Daily summary and saving stores the digest rule enabled" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"recipients" => "ops@example.com", "rules" => %{"digest" => "true"}})
    |> render_submit()

    assert stored_rule(:digest).enabled
    assert has_element?(view, ".rule input[type=checkbox][checked][aria-label='Daily summary']")
  end

  test "turning on An error keeps happening and saving stores the still happening rule enabled" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"recipients" => "ops@example.com", "rules" => %{"still_happening" => "true"}})
    |> render_submit()

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

  test "saving stores the email channel enabled with the recipients and each rule's switch" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{
      "recipients" => "a@example.com, b@example.com",
      "rules" => %{"new" => "true", "regression" => "false"}
    })
    |> render_submit()

    assert %ChannelSetting{enabled: true, config: %{"recipients" => ["a@example.com", "b@example.com"]}} =
             stored_email_channel()

    assert stored_rule(:new).enabled
    refute stored_rule(:regression).enabled
    assert has_element?(view, ".flash--info", "Email settings saved.")
  end

  test "saving reads recipients separated by commas or new lines, ignoring blanks and repeats" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{"recipients" => " a@example.com,\nb@example.com\n\n, a@example.com "})
    |> render_submit()

    assert %ChannelSetting{config: %{"recipients" => ["a@example.com", "b@example.com"]}} = stored_email_channel()
  end

  test "saving an invalid address stores nothing and shows which address is invalid" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view
    |> form("#email-settings", %{
      "recipients" => "ok@example.com, not-an-address",
      "rules" => %{"regression" => "false"}
    })
    |> render_submit()

    assert stored_email_channel() == nil
    assert stored_rule(:regression) == nil
    assert has_element?(view, "#recipients-errors", "not-an-address is not an email address")
    refute has_element?(view, "#recipients-errors", "ok@example.com")
    refute has_element?(view, ".flash--info")
  end

  test "saving without recipients stores nothing and asks for one" do
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"recipients" => " "}) |> render_submit()

    assert stored_email_channel() == nil
    assert has_element?(view, "#recipients-errors", "must list at least one email address")
  end

  test "sending a test email delivers one test email to the form's recipients" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"recipients" => "a@example.com, b@example.com"}) |> render_change()
    view |> element("button", "Send test email") |> render_click()

    assert_email_sent(
      from: {"", "errors@example.com"},
      to: [{"", "a@example.com"}, {"", "b@example.com"}],
      subject: "[Imison] Test email"
    )

    refute_email_sent()
    assert has_element?(view, ".flash--info", "Test email sent to a@example.com, b@example.com.")
    assert stored_email_channel() == nil
  end

  test "sending a test email with a saved email channel records no delivery" do
    set_swoosh_global()
    start_mailing_imison()
    put_email_channel(["ops@example.com"])
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> element("button", "Send test email") |> render_click()

    assert_email_sent(subject: "[Imison] Test email", to: [{"", "ops@example.com"}])
    assert Repo.all(Delivery) == []
  end

  test "the test email says that delivery works" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"recipients" => "a@example.com"}) |> render_change()
    view |> element("button", "Send test email") |> render_click()

    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ "Email delivery from Imison works"
  end

  test "sending a test email to an invalid address sends nothing and shows which address is invalid" do
    set_swoosh_global()
    start_mailing_imison()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    view |> form("#email-settings", %{"recipients" => "not-an-address"}) |> render_change()
    view |> element("button", "Send test email") |> render_click()

    refute_email_sent()
    assert has_element?(view, "#recipients-errors", "not-an-address is not an email address")
  end

  test "a mailer that returns an error shows it and logs the failure" do
    start_mailing_imison(mailer: FailingMailer)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"recipients" => "a@example.com"}) |> render_change()

    log = capture_log(fn -> view |> element("button", "Send test email") |> render_click() end)

    assert has_element?(view, ".flash--error", "Couldn't send the test email: :smtp_unavailable")
    assert log =~ "Imison failed to deliver a notification"
  end

  test "a mailer that raises shows the error and the screen keeps working" do
    start_mailing_imison(mailer: RaisingMailer)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"recipients" => "a@example.com"}) |> render_change()

    log = capture_log(fn -> view |> element("button", "Send test email") |> render_click() end)

    assert has_element?(view, ".flash--error", "Couldn't send the test email")
    assert has_element?(view, ".flash--error", "SMTP connection refused")
    assert log =~ "SMTP connection refused"
    assert render(view) =~ "Send test email"
  end

  test "without a mailer the test email fails with an error message" do
    start_imison(name: Dashboard, enabled: false, from: "errors@example.com")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")
    view |> form("#email-settings", %{"recipients" => "a@example.com"}) |> render_change()

    capture_log(fn -> view |> element("button", "Send test email") |> render_click() end)

    assert has_element?(view, ".flash--error", "Couldn't send the test email: :mailer_not_configured")
  end

  test "when the email channel isn't in channels the screen says how to enable it, with no form" do
    start_imison(name: Dashboard, enabled: false, channels: [])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/notifications")

    assert has_element?(view, ".channel .empty__title", "Email isn't available")
    assert has_element?(view, ".channel .empty__text", "swoosh")
    refute has_element?(view, "#email-settings")
    refute has_element?(view, "button", "Send test email")
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
    |> LazyHTML.query(".rule input[type=checkbox]")
    |> Enum.count()
  end

  defp stored_email_channel, do: Repo.get_by(ChannelSetting, type: Email.type())

  defp stored_rule(trigger), do: Repo.get_by(Rule, trigger: trigger)
end
