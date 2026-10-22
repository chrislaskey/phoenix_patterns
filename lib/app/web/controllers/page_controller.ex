defmodule App.Web.PageController do
  use App.Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
