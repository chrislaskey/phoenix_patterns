defmodule App.Web.Api.UserTokens do
  @moduledoc """
  The `user_tokens` requests: a client managing the API token it connected
  with. A client cannot see or change any other token.

    * `user_tokens.update` - replaces the token and replies with the new one.
    * `user_tokens.delete` - deletes the token.

  Every socket connected with the token is closed after the reply, so a
  client reconnects with its new token or not at all.
  """

  import Phoenix.Channel

  alias App.Data.Accounts
  alias App.Web.UserAuth

  def handle("update", _params, socket) do
    %{current_scope: scope, api_token: api_token} = socket.assigns

    case Accounts.update_user_api_token(scope, api_token) do
      {:ok, {token, deleted_token}} -> reply_and_disconnect(socket, %{token: token}, deleted_token)
      {:error, :not_found} -> {:reply, {:error, %{reason: "not_found"}}, socket}
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
