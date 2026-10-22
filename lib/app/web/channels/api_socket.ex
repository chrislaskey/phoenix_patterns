defmodule App.Web.ApiSocket do
  @moduledoc """
  The websocket clients use for the API, mounted at `/api`.

  Every client request goes through the one `"api"` channel. See
  `App.Web.ApiChannel` for the request format.
  """

  use Phoenix.Socket

  channel "api", App.Web.ApiChannel

  # Authentication is not handled yet, so every connection is accepted.
  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
