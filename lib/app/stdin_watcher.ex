defmodule App.StdinWatcher do
  @moduledoc """
  Stops the system when standard input closes.

  A desktop app that starts the standalone binary keeps a pipe open to its
  standard input. When the desktop app quits or crashes, the operating system
  closes the pipe and the server stops with it, instead of being left running
  in the background.

  Only runs when `config :app, :exit_on_stdin_close, true` is set, which
  config/runtime.exs does for a standalone binary started with
  EXIT_ON_STDIN_CLOSE=1.
  """
  use Task, restart: :transient

  require Logger

  def start_link(_opts) do
    if Application.get_env(:app, :exit_on_stdin_close, false) do
      Task.start_link(&watch/0)
    else
      :ignore
    end
  end

  defp watch do
    case IO.read(:stdio, :line) do
      data when is_binary(data) ->
        watch()

      _eof_or_error ->
        Logger.info("Standard input closed, shutting down")
        System.stop(0)
    end
  end
end
