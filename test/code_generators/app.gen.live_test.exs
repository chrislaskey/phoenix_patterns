defmodule Mix.Tasks.App.Gen.LiveTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  # The project built by `test_project/1` is called `:test`, so its web
  # module is `TestWeb`. The router is the one `mix phx.new` generates, cut
  # down to what the generator looks for: the scope at "/" that pipes
  # through :browser. The project also carries this repository's
  # `.igniter.exs`, which keeps LiveViews in the live/ folder, and its
  # `.formatter.exs`, so the written code is formatted the same way.
  @router """
  defmodule TestWeb.Router do
    use TestWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", TestWeb do
      pipe_through :browser

      get "/", PageController, :home
    end
  end
  """

  defp project(files \\ %{}) do
    test_project(
      files:
        Map.merge(
          %{
            ".igniter.exs" => File.read!(".igniter.exs"),
            ".formatter.exs" => File.read!(".formatter.exs"),
            "lib/test_web/router.ex" => @router
          },
          files
        )
    )
  end

  defp generate(igniter, name, path) do
    Igniter.compose_task(igniter, "app.gen.live", [name, path])
  end

  test "creates the LiveView with the layout and an id on its root element" do
    project()
    |> generate("Dashboard", "/dashboard")
    |> assert_creates("lib/test_web/live/dashboard_live.ex", fn file ->
      assert file =~ "defmodule TestWeb.DashboardLive do"
      assert file =~ "use TestWeb, :live_view"
      assert file =~ "<Layouts.app flash={@flash}>"
      assert file =~ ~s(<div id="dashboard">)
    end)
  end

  test "creates a test that loads the page and looks for the id" do
    project()
    |> generate("Dashboard", "/dashboard")
    |> assert_creates("test/test_web/live/dashboard_live_test.exs", fn file ->
      assert file =~ "defmodule TestWeb.DashboardLiveTest do"
      assert file =~ "use TestWeb.ConnCase, async: true"
      assert file =~ ~s[live(conn, ~p"/dashboard")]
      assert file =~ ~s[has_element?(view, "#dashboard")]
    end)
  end

  test "adds the route to the browser scope" do
    project()
    |> generate("Dashboard", "/dashboard")
    |> assert_has_patch("lib/test_web/router.ex", """
    + |    live "/dashboard", DashboardLive
    """)
  end

  test "does not double the Live suffix" do
    project()
    |> generate("DashboardLive", "/dashboard")
    |> assert_creates("lib/test_web/live/dashboard_live.ex")
    |> assert_has_patch("lib/test_web/router.ex", """
    + |    live "/dashboard", DashboardLive
    """)
  end

  test "nests a dotted name in a folder and in the module" do
    project()
    |> generate("Admin.Reports", "/admin/reports")
    |> assert_creates("lib/test_web/live/admin/reports_live.ex", fn file ->
      assert file =~ "defmodule TestWeb.Admin.ReportsLive do"
      assert file =~ ~s(<div id="admin-reports">)
      assert file =~ "<.header>Reports</.header>"
    end)
    |> assert_creates("test/test_web/live/admin/reports_live_test.exs")
    |> assert_has_patch("lib/test_web/router.ex", """
    + |    live "/admin/reports", Admin.ReportsLive
    """)
  end

  test "keeps the files in the live folder when the changes are applied" do
    igniter =
      project()
      |> generate("Admin.Reports", "/admin/reports")
      |> apply_igniter!()

    assert Igniter.exists?(igniter, "lib/test_web/live/admin/reports_live.ex")
    assert Igniter.exists?(igniter, "test/test_web/live/admin/reports_live_test.exs")
  end

  test "refuses when the module already exists" do
    project(%{
      "lib/test_web/live/dashboard_live.ex" => "defmodule TestWeb.DashboardLive do\nend\n"
    })
    |> generate("Dashboard", "/dashboard")
    |> assert_has_issue(&(&1 =~ "TestWeb.DashboardLive already exists"))
    |> assert_unchanged("lib/test_web/router.ex")
  end
end
