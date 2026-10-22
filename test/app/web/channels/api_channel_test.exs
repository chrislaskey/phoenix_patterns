defmodule App.Web.ApiChannelTest do
  use App.Web.ChannelCase

  import App.Data.UsersFixtures

  alias App.Web.ApiChannel
  alias App.Web.ApiSocket

  setup do
    {:ok, _reply, socket} =
      ApiSocket
      |> socket(nil, %{current_scope: user_scope_fixture()})
      |> subscribe_and_join(ApiChannel, "api")

    %{socket: socket}
  end

  test "replies with an error for an unknown request", %{socket: socket} do
    ref = push(socket, "unknown.thing", %{})

    assert_reply ref, :error, %{reason: "unknown_request", event: "unknown.thing"}
  end
end
