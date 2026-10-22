defmodule App.Web.ApiChannel do
  @moduledoc """
  The single channel for all API requests.

  Clients join the `"api"` topic and push one event per request. The event
  name is the request and the payload is its params:

      channel.push("user_tokens.update", {})

  Every request runs as `socket.assigns.current_scope`, the user of the
  API token the client connected with (see `App.Web.ApiSocket`).
  `App.Router.Api` sends each request to the module that handles it.
  """

  use Phoenix.Channel

  alias App.Router.Api, as: ApiRouter

  @impl true
  def join("api", _params, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in(request, params, socket) do
    ApiRouter.route(request, params, socket)
  end
end
