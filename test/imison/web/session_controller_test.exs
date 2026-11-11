defmodule Imison.Web.SessionControllerTest do
  use Imison.ConnCase, async: false

  import Imison.Test.CaptureHelpers

  alias Imison.Test.Dashboard

  test "the login page shows the sign-in form without a session" do
    start_imison(name: Dashboard, enabled: false)

    document = browser_conn() |> get("/errors/login") |> html_response(200) |> LazyHTML.from_document()

    assert [_form] = document |> LazyHTML.query("form.auth__card[method=post]") |> Enum.to_list()
    assert document |> LazyHTML.query("form.auth__card") |> LazyHTML.attribute("action") == ["/errors/login"]
    assert document |> LazyHTML.query("h1.auth__title") |> LazyHTML.text() == "Sign in"
    assert [_username] = document |> LazyHTML.query("input#username[name=username]") |> Enum.to_list()
    assert [_password] = document |> LazyHTML.query("input#password[name=password][type=password]") |> Enum.to_list()
    assert document |> LazyHTML.query("button[type=submit]") |> LazyHTML.text() == "Sign in"
    assert document |> LazyHTML.query(".flash--error") |> Enum.to_list() == []
  end

  test "the login page makes no third-party requests" do
    start_imison(name: Dashboard, enabled: false)

    document = browser_conn() |> get("/errors/login") |> html_response(200) |> LazyHTML.from_document()

    urls =
      (document |> LazyHTML.query("[href]") |> LazyHTML.attribute("href")) ++
        (document |> LazyHTML.query("[src]") |> LazyHTML.attribute("src"))

    assert urls != []
    assert Enum.all?(urls, &String.starts_with?(&1, "/errors"))
  end

  test "the configured username and password sign in and open the dashboard" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn =
      login_conn
      |> next_browser_conn()
      |> post("/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "secret"})

    assert redirected_to(conn) == "/errors"
    assert {:ok, view, _html} = conn |> next_browser_conn() |> live("/errors")
    assert has_element?(view, ".page__title", "Errors")
  end

  test "signing in at another mount path redirects to that dashboard" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/admin/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn =
      login_conn
      |> next_browser_conn()
      |> post("/admin/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "secret"})

    assert redirected_to(conn) == "/admin/errors"
    assert {:ok, _view, _html} = conn |> next_browser_conn() |> live("/admin/errors")
  end

  test "a wrong password shows an error and does not sign in" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn =
      login_conn
      |> next_browser_conn()
      |> post("/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "wrong"})

    document = conn |> html_response(401) |> LazyHTML.from_document()

    assert document |> LazyHTML.query(".flash--error[role=alert]") |> LazyHTML.text() == "Wrong username or password."
    assert [_form] = document |> LazyHTML.query("form.auth__card") |> Enum.to_list()

    assert {:error, {:redirect, %{to: "/errors/login"}}} = conn |> next_browser_conn() |> live("/errors")
  end

  test "the error page does not show the submitted password" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn =
      login_conn
      |> next_browser_conn()
      |> post("/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "almost-secret"})

    refute html_response(conn, 401) =~ "almost-secret"
  end

  test "a missing username and password do not sign in" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn = login_conn |> next_browser_conn() |> post("/errors/login", %{"_csrf_token" => token})

    assert html_response(conn, 401) =~ "Wrong username or password."
    assert {:error, {:redirect, %{to: "/errors/login"}}} = conn |> next_browser_conn() |> live("/errors")
  end

  test "the session cookie keeps the visitor signed in on another node sharing the secret key base" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    signed_in_conn =
      login_conn
      |> next_browser_conn()
      |> post("/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "secret"})

    %{value: session_cookie} = signed_in_conn.resp_cookies["_imison_test_key"]

    another_node_conn = put_req_cookie(browser_conn(), "_imison_test_key", session_cookie)

    assert {:ok, view, _html} = live(another_node_conn, "/errors")
    assert has_element?(view, ".page__title", "Errors")
  end

  test "signing out returns to the login page and the dashboard redirects to it again" do
    start_imison(name: Dashboard, enabled: false)
    signed_in_conn = sign_in("/errors", "admin", "secret")
    {:ok, view, _html} = live(signed_in_conn, "/errors")

    sign_out_form = form(view, ".topbar form[action='/errors/logout']")
    conn = submit_form(sign_out_form, next_browser_conn(signed_in_conn))

    assert redirected_to(conn) == "/errors/login"
    assert {:error, {:redirect, %{to: "/errors/login"}}} = conn |> next_browser_conn() |> live("/errors")
  end

  test "a password change signs out existing sessions" do
    start_imison(name: Dashboard, enabled: false)
    signed_in_conn = sign_in("/errors", "admin", "secret")

    stop_supervised!(Dashboard)
    start_imison(name: Dashboard, enabled: false, password: "changed")

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(signed_in_conn, "/errors")
  end

  test "the new password signs in after a password change" do
    start_imison(name: Dashboard, enabled: false, password: "changed")

    signed_in_conn = sign_in("/errors", "admin", "changed")

    assert {:ok, _view, _html} = live(signed_in_conn, "/errors")
  end
end
