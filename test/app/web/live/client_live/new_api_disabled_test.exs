defmodule App.Web.ClientLive.NewApiDisabledTest do
  use App.Web.ConnCase

  import Phoenix.LiveViewTest
  import App.Data.UsersFixtures

  setup %{conn: conn} do
    Application.put_env(:app, :api_socket, false)
    on_exit(fn -> Application.put_env(:app, :api_socket, true) end)

    %{conn: log_in_user(conn, user_fixture())}
  end

  test "does not create a token when the API is off", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/client/new")

    render_hook(view, "client_detected", %{"available" => true})

    assert has_element?(view, "#client-api-disabled")
    refute has_element?(view, "#client-connecting")
    refute_push_event(view, "client_token", _)
  end
end
