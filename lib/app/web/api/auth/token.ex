defmodule App.Web.Api.Auth.Token do
  @moduledoc """
  The `auth.token` requests: a client managing the API token it connected
  with. A client cannot see or change any other token.

    * `auth.token.get` - when the token was created and when it expires.
    * `auth.token.update` - replaces the token and replies with the new one
      and when it expires.
    * `auth.token.delete` - deletes the token.

  After an update or a delete, every socket connected with the old token is
  closed after the reply, so a client reconnects with its new token or not
  at all.
  """

  import Phoenix.Channel

  alias App.Data.Accounts
  alias App.Data.UserToken
  alias App.Web.UserAuth

  def handle("get", _params, socket) do
    api_token = socket.assigns.api_token

    {:reply, {:ok, %{inserted_at: api_token.inserted_at, expires_at: UserToken.expires_at(api_token)}},
     socket}
  end

  def handle("update", _params, socket) do
    %{current_scope: scope, api_token: api_token} = socket.assigns

    case Accounts.update_user_api_token(scope, api_token) do
      {:ok, {token, new_token, deleted_token}} ->
        payload = %{token: token, expires_at: UserToken.expires_at(new_token)}
        reply_and_disconnect(socket, payload, deleted_token)

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  def handle("delete", _params, socket) do
    %{current_scope: scope, api_token: api_token} = socket.assigns

    case Accounts.delete_user_api_token(scope, api_token) do
      {:ok, deleted_token} -> reply_and_disconnect(socket, %{}, deleted_token)
      {:error, :not_found} -> {:reply, {:error, %{reason: "not_found"}}, socket}
    end
  end

  def handle(_action, _params, _socket), do: :unknown

  # Replies before disconnecting, since the disconnect closes this very
  # socket. Both messages go from this process to the socket's, so they
  # arrive in order.
  defp reply_and_disconnect(socket, payload, deleted_token) do
    reply(socket_ref(socket), {:ok, payload})
    UserAuth.disconnect_sessions([deleted_token])
    {:noreply, socket}
  end
end
