defmodule App.Web.ApiChannel do
  @moduledoc """
  The single channel for all API requests.

  Clients join the `"api"` topic and push one event per request. The event
  name is the request and the payload is its params:

      channel.push("users.list", {})

  Requests are not mapped yet, so every request replies with an
  `"unknown_request"` error.
  """

  use Phoenix.Channel

  @impl true
  def join("api", _params, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in(event, _params, socket) do
    {:reply, {:error, %{reason: "unknown_request", event: event}}, socket}
  end
end
