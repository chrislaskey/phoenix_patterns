defmodule App.Web.Api.Auth.TokenTest do
  use App.Web.ChannelCase

  import App.Data.UsersFixtures

  alias App.Data.Accounts
  alias App.Data.UserToken
  alias App.Web.ApiChannel
  alias App.Web.ApiSocket

  setup do
    user = user_fixture()
    token = Accounts.generate_user_api_token(user)
    {:ok, socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: token})
    {:ok, _reply, socket} = subscribe_and_join(socket, ApiChannel, "api")
    @endpoint.subscribe(ApiSocket.id(socket))

    %{user: user, token: token, socket: socket}
  end

  describe "auth.token.get" do
    test "replies with when the token was created and expires", %{socket: socket} do
      api_token = socket.assigns.api_token

      ref = push(socket, "auth.token.get", %{})

      assert_reply ref, :ok, %{inserted_at: inserted_at, expires_at: expires_at}
      assert inserted_at == api_token.inserted_at
      assert expires_at == DateTime.add(api_token.inserted_at, 365, :day)
      refute_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end

  describe "auth.token.update" do
    test "replies with a new token and disconnects the old one", %{token: token, socket: socket} do
      ref = push(socket, "auth.token.update", %{})

      assert_reply ref, :ok, %{token: new_token, expires_at: expires_at}
      assert expires_at == UserToken.expires_at(Accounts.get_user_api_token(new_token))
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      refute Accounts.get_user_api_token(token)
      assert {:ok, _socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: new_token})
    end

    test "leaves the user's other tokens alone", %{user: user, socket: socket} do
      other_token = Accounts.generate_user_api_token(user)

      ref = push(socket, "auth.token.update", %{})

      assert_reply ref, :ok, %{token: _new_token}
      assert Accounts.get_user_api_token(other_token)
    end
  end

  describe "auth.token.delete" do
    test "deletes the token and disconnects it", %{token: token, socket: socket} do
      ref = push(socket, "auth.token.delete", %{})

      assert_reply ref, :ok, %{}
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      refute Accounts.get_user_api_token(token)
    end

    test "ignores an id and leaves the user's other tokens alone", %{user: user, socket: socket} do
      other_token = Accounts.generate_user_api_token(user)
      other_id = Accounts.get_user_api_token(other_token).id

      ref = push(socket, "auth.token.delete", %{"id" => other_id})

      assert_reply ref, :ok, %{}
      assert Accounts.get_user_api_token(other_token)
    end
  end

  test "replies with an error for an unknown action", %{socket: socket} do
    ref = push(socket, "auth.token.list", %{})

    assert_reply ref, :error, %{reason: "unknown_request", event: "auth.token.list"}
  end
end
