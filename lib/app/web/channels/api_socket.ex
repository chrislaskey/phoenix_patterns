defmodule App.Web.ApiSocket do
  @moduledoc """
  The websocket clients use for the API, mounted at `/api`.

  Every client request goes through the one `"api"` channel. See
  `App.Web.ApiChannel` for the request format.

  ## Authentication

  A client connects with an API token from
  `App.Data.Accounts.generate_user_api_token/1`. A connection without a
  valid token is refused with a 403.

  The token goes in the `Sec-WebSocket-Protocol` header of the upgrade
  request, not in the URL, so it stays out of logs. This is the
  `auth_token` option of `Phoenix.Endpoint.socket/3`. The header lists
  `phoenix` and the token, base64 encoded without padding behind a
  `base64url.bearer.phx.` prefix:

      Sec-WebSocket-Protocol: phoenix, base64url.bearer.phx.<base64 of the token>

  The `phoenix` JavaScript client does this with its `authToken` option.

  Refuses every connection unless `API_SOCKET=true`, see `config/runtime.exs`.

  The socket assigns `:current_scope` and `:api_token`, the row of the
  token it connected with. Its `id/1` is the token's session topic, so passing the token to
  `App.Web.UserAuth.disconnect_sessions/1` closes the connection. Changing
  the password keeps API tokens, and their connections stay open.
  """

  use Phoenix.Socket

  alias App.Data.Accounts
  alias App.Data.UserToken
  alias App.Web.Scope
  alias App.Web.UserAuth

  channel "api", App.Web.ApiChannel

  def enabled?, do: Application.get_env(:app, :api_socket, false) == true

  @impl true
  def connect(_params, socket, %{auth_token: token}) when is_binary(token) do
    with true <- enabled?(),
         %UserToken{user: user} = user_token <- Accounts.get_user_api_token(token) do
      {:ok,
       socket
       |> assign(:current_scope, Scope.for_user(user))
       |> assign(:api_token, %{user_token | user: nil})}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: UserAuth.user_session_topic(socket.assigns.api_token.token)
end
