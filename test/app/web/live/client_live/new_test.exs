defmodule App.Web.ClientLive.NewTest do
  use App.Web.ConnCase, async: true

  import Phoenix.LiveViewTest
  import App.Data.UsersFixtures

  alias App.Data.Accounts
  alias App.Data.UserToken

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp detect_client(view) do
    render_hook(view, "client_detected", %{"available" => true})
    assert_push_event(view, "client_token", %{token: token})
    token
  end

  describe "New client page" do
    test "renders the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      assert has_element?(view, "#client-new")
    end

    test "waits for the hook before doing anything", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      refute has_element?(view, "#client-connecting")
      refute has_element?(view, "#client-unavailable")
    end

    test "does not create a token outside the app", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      render_hook(view, "client_detected", %{"available" => false})

      assert has_element?(view, "#client-unavailable")
      refute has_element?(view, "#client-connecting")
      refute_push_event(view, "client_token", _)
    end

    test "hands the client an API token as soon as it is found", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      token = detect_client(view)

      assert %UserToken{user_id: user_id, context: "api"} = Accounts.get_user_api_token(token)
      assert user_id == user.id
      assert has_element?(view, "#client-connecting")
    end

    test "moves on to the app once the client has the token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      detect_client(view)
      render_hook(view, "connected", %{})

      assert_redirect(view, ~p"/")
    end

    test "shows the error when the client refuses the token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      detect_client(view)
      render_hook(view, "connect_failed", %{"error" => "The token is not a base64url string"})

      assert view |> element("#client-connect-error") |> render() =~
               "The token is not a base64url string"

      refute has_element?(view, "#client-connecting")
    end

    test "hands over a new token when trying again", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/client/new")

      first = detect_client(view)
      render_hook(view, "connect_failed", %{"error" => "oops"})

      view |> element("#client-connect") |> render_click()
      assert_push_event(view, "client_token", %{token: second})

      assert first != second
      assert Accounts.get_user_api_token(second)
      assert has_element?(view, "#client-connecting")
      refute has_element?(view, "#client-connect-error")
    end
  end

  describe "logging in from the client" do
    test "sends a logged out user to log in" do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(build_conn(), ~p"/client/new")

      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "comes back to the page after logging in", %{user: user} do
      conn = get(build_conn(), ~p"/client/new")
      assert redirected_to(conn) == ~p"/users/log-in"

      user = set_password(user)

      conn =
        conn
        |> recycle()
        |> post(~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/client/new"
    end
  end
end
