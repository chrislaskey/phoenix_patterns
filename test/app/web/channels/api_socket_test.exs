defmodule App.Web.ApiSocketTest do
  use App.Web.ChannelCase

  import App.Data.UsersFixtures

  alias App.Data.Accounts
  alias App.Data.UserTokens
  alias App.Web.ApiSocket

  setup do
    user = user_fixture()
    %{user: user, token: Accounts.generate_user_api_token(user)}
  end

  test "connects as the user of the API token", %{user: user, token: token} do
    assert {:ok, socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
    assert socket.assigns.current_scope.user.id == user.id
    assert "users_sessions:" <> _ = ApiSocket.id(socket)
  end

  test "refuses a connection without a token" do
    assert :error = connect(ApiSocket, %{}, connect_info: %{auth_token: nil})
    assert :error = connect(ApiSocket, %{})
  end

  test "refuses an unknown token" do
    assert :error = connect(ApiSocket, %{}, connect_info: %{auth_token: "oops"})
  end

  test "refuses a session token", %{user: user} do
    token = Accounts.generate_user_session_token(user)

    assert :error = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
  end

  test "is disconnected through its token's session topic", %{user: user, token: token} do
    {:ok, socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
    @endpoint.subscribe(ApiSocket.id(socket))

    App.Web.UserAuth.disconnect_sessions(UserTokens.list(filters: [user_id: user.id]))

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
  end

  test "refuses every connection when the API is off", %{token: token} do
    Application.put_env(:app, :api_socket, false)
    on_exit(fn -> Application.put_env(:app, :api_socket, true) end)

    refute ApiSocket.enabled?()
    assert :error = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
  end

  test "stays connected when the user changes their password", %{user: user, token: token} do
    {:ok, {_user, expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    assert expired_tokens == []
    assert {:ok, _socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
  end
end
