defmodule App.Web.ClientLive.New do
  @moduledoc """
  Hands an app client, like a desktop app's webview, an API token for
  `App.Web.ApiSocket` through the `ClientConnect` hook in
  `assets/js/app_client.js`. The client opens this page whenever it needs a
  token, logging in first if needed.
  """

  use App.Web, :live_view

  alias App.Data.Accounts
  alias App.Web.ApiSocket

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Connect this app",
       api_enabled: ApiSocket.enabled?(),
       client: nil,
       status: :idle,
       error: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="client-new" phx-hook="ClientConnect" class="mx-auto max-w-lg space-y-6 text-center">
        <.header>
          Connect this app
          <:subtitle>
            Give this app an API token for {@current_scope.user.email}
          </:subtitle>
        </.header>

        <p :if={!@api_enabled} id="client-api-disabled" class="text-base-content/70">
          The API is turned off on this server, so the app can't connect to it.
        </p>

        <p :if={@api_enabled && @client == false} id="client-unavailable" class="text-base-content/70">
          This page only works inside the app. Open it from the app's Log in button.
        </p>

        <p :if={@status == :connecting} id="client-connecting" class="text-base-content/70">
          Connecting the app...
        </p>

        <div :if={@status == :failed} class="space-y-4">
          <p id="client-connect-error" class="text-error">
            Could not hand the token to the app: {@error}
          </p>
          <.button
            id="client-connect"
            variant="primary"
            phx-click="connect"
            phx-disable-with="Connecting..."
          >
            Try again
          </.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("client_detected", %{"available" => true}, %{assigns: %{api_enabled: true}} = socket) do
    {:noreply, socket |> assign(:client, true) |> hand_over_token()}
  end

  def handle_event("client_detected", _params, socket) do
    {:noreply, assign(socket, :client, false)}
  end

  def handle_event("connect", _params, %{assigns: %{client: true}} = socket) do
    {:noreply, hand_over_token(socket)}
  end

  def handle_event("connected", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "The app is connected.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("connect_failed", %{"error" => error}, socket) do
    {:noreply, assign(socket, status: :failed, error: to_string(error))}
  end

  defp hand_over_token(socket) do
    token = Accounts.generate_user_api_token(socket.assigns.current_scope.user)

    socket
    |> assign(status: :connecting, error: nil)
    |> push_event("client_token", %{token: token})
  end
end
