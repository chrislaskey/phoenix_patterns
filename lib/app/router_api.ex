defmodule App.Router.Api do
  @moduledoc """
  Sends each request of `App.Web.ApiChannel` to the module that handles it.

  A request is named `<resource>.<action>`, like `user_tokens.update`. The
  router picks the module from the name and calls its `handle/3` with the
  action, the params and the socket:

      App.Web.Api.UserTokens.handle("update", params, socket)

  `handle/3` returns what `c:Phoenix.Channel.handle_in/3` returns, or
  `:unknown` for an action it does not have. The router replies with an
  `"unknown_request"` error for an unknown resource or action.

  Matching is plain code rather than function clauses, so rules beyond the
  two parts of the name, like a third part or a check on the user, go here.
  """

  alias App.Web.Api

  def route(request, params, socket) do
    result =
      case String.split(request, ".") do
        ["user_tokens", action] -> Api.UserTokens.handle(action, params, socket)
        _ -> :unknown
      end

    case result do
      :unknown -> {:reply, {:error, %{reason: "unknown_request", event: request}}, socket}
      result -> result
    end
  end
end
