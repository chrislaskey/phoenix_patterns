defmodule App.Web.LayoutsTest do
  use App.Web.ConnCase, async: true

  test "the root layout inlines the theme script in <head>", %{conn: conn} do
    script = File.read!("assets/js/theme_script.js")

    head =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("head > script:not([src])")
      |> LazyHTML.text()

    assert String.trim(head) == String.trim(script)
  end
end
