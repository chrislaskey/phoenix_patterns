defmodule App.Web.Api.UserTokensTest do
  use App.Web.ChannelCase

  import App.Data.UsersFixtures

  alias App.Data.Accounts
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

  describe "user_tokens.update" do
    test "replies with a new token and disconnects the old one", %{token: token, socket: socket} do
      ref = push(socket, "user_tokens.update", %{})

      assert_reply ref, :ok, %{token: new_token}
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      refute Accounts.get_user_api_token(token)
      assert {:ok, _socket} = connect(ApiSocket, %{}, connect_info: %{auth_token: new_token})
    end

    test "leaves the user's other tokens alone", %{user: user, socket: socket} do
      other_token = Accounts.generate_user_api_token(user)

      ref = push(socket, "user_tokens.update", %{})

      assert_reply ref, :ok, %{token: _new_token}
      assert Accounts.get_user_api_token(other_token)
    end
  end

  describe "user_tokens.delete" do
    test "deletes the token and disconnects it", %{token: token, socket: socket} do
      ref = push(socket, "user_tokens.delete", %{})

      assert_reply ref, :ok, %{}
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
      refute Accounts.get_user_api_token(token)
    end

    test "ignores an id and leaves the user's other tokens alone", %{user: user, socket: socket} do
      other_token = Accounts.generate_user_api_token(user)
      other_id = Accounts.get_user_api_token(other_token).id

      ref = push(socket, "user_tokens.delete", %{"id" => other_id})

      assert_reply ref, :ok, %{}
      assert Accounts.get_user_api_token(other_token)
    end
  end

  test "replies with an error for an unknown action", %{socket: socket} do
    ref = push(socket, "user_tokens.list", %{})

    assert_reply ref, :error, %{reason: "unknown_request", event: "user_tokens.list"}
  end
end
