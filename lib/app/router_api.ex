defmodule App.Router.Api do
  @moduledoc """
  Sends each request of `App.Web.ApiChannel` to the module that handles it.

  A request is named `<domain>.<resource>.<action>`, like
  `auth.token.update`:

    * the domain is the part of the product the request belongs to, like
      `auth` for the connection's own credential or `settings`
    * the resource is plural, unless the domain only ever has one of it, like
      the connection's token in `auth`
    * the action is `get`, `list`, `create`, `update` or `delete`

  Every request has all three parts. The router picks the module from the
  domain and resource and calls its `handle/3` with the action, the params
  and the socket:

      App.Web.Api.Auth.Token.handle("update", params, socket)

  `handle/3` returns what `c:Phoenix.Channel.handle_in/3` returns, or
  `:unknown` for an action it does not have. The router replies with an
  `"unknown_request"` error for an unknown domain, resource or action.

  Matching is plain code rather than function clauses, so rules beyond the
  parts of the name, like a check on the user, go here.
  """

  alias App.Web.Api

  def route(request, params, socket) do
    result =
      case String.split(request, ".") do
        ["auth", "token", action] -> Api.Auth.Token.handle(action, params, socket)
        _ -> :unknown
      end

    case result do
      :unknown -> {:reply, {:error, %{reason: "unknown_request", event: request}}, socket}
      result -> result
    end
  end
end
