defmodule Mix.Tasks.App.Gen.Live do
  @shortdoc "Generates a LiveView, its route and its test"

  @example "mix app.gen.live Dashboard /dashboard"

  @moduledoc """
  #{@shortdoc}. Use it for any new page instead of writing the module by hand.

      $ #{@example}

  Creates the LiveView, adds its route to the browser scope of the router and
  creates a test that loads the page:

      lib/my_app_web/live/dashboard_live.ex
      test/my_app_web/live/dashboard_live_test.exs

      live "/dashboard", DashboardLive

  The first argument names the page and the second is its path. The module
  always ends in `Live`, so `Dashboard` and `DashboardLive` give the same
  result. A dotted name makes a nested module and folder:

      $ mix app.gen.live Admin.Reports /admin/reports
      lib/my_app_web/live/admin/reports_live.ex

  The generated template starts with `<Layouts.app flash={@flash}>` and gives
  its root element an id, which the test uses. The route goes in the scope at
  `"/"` that pipes through `:browser`. When a different scope is needed, run
  the task and move the one line.

  The task fails, and changes nothing, when the module already exists. Pass
  `--dry-run` to print the changes without writing them and `--yes` to skip
  the confirmation. See `priv/code_generators/README.md` for how the
  generators work and how to add one.
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :app,
      example: @example,
      positional: [:name, :path]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    %{name: name, path: path} = igniter.args.positional
    web_module = Igniter.Libs.Phoenix.web_module(igniter)
    suffix = suffix(name)
    module = Module.concat(web_module, suffix)

    case Igniter.Project.Module.module_exists(igniter, module) do
      {true, igniter} ->
        Igniter.add_issue(igniter, "#{inspect(module)} already exists, nothing was generated.")

      {false, igniter} ->
        igniter
        |> Igniter.create_new_file(
          file("lib", web_module, suffix, ".ex"),
          live_view(web_module, suffix)
        )
        |> Igniter.create_new_file(
          file("test", web_module, suffix, "_test.exs"),
          test(web_module, suffix, path)
        )
        |> Igniter.Libs.Phoenix.append_to_scope("/", ~s(live "#{path}", #{inspect(suffix)}),
          arg2: web_module,
          with_pipelines: [:browser]
        )
    end
  end

  # `Dashboard`, `DashboardLive` and `Admin.Dashboard` give `DashboardLive`,
  # `DashboardLive` and `Admin.DashboardLive`.
  defp suffix(name) do
    Module.concat([String.trim_trailing(name, "Live") <> "Live"])
  end

  # lib/my_app_web/live/admin/dashboard_live.ex
  defp file(root, web_module, suffix, extension) do
    Path.join([root, Macro.underscore(web_module), "live", Macro.underscore(suffix) <> extension])
  end

  # The id of the root element and the selector in the test: `admin-dashboard`
  defp dom_id(suffix) do
    suffix
    |> Macro.underscore()
    |> String.trim_trailing("_live")
    |> String.replace(["/", "_"], "-")
  end

  # The page title and heading: `Dashboard`
  defp title(suffix) do
    suffix
    |> Module.split()
    |> List.last()
    |> String.trim_trailing("Live")
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp live_view(web_module, suffix) do
    """
    defmodule #{inspect(web_module)}.#{inspect(suffix)} do
      use #{inspect(web_module)}, :live_view

      @impl true
      def mount(_params, _session, socket) do
        {:ok, assign(socket, :page_title, "#{title(suffix)}")}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <Layouts.app flash={@flash}>
          <div id="#{dom_id(suffix)}">
            <.header>#{title(suffix)}</.header>
          </div>
        </Layouts.app>
        \"\"\"
      end
    end
    """
  end

  defp test(web_module, suffix, path) do
    """
    defmodule #{inspect(web_module)}.#{inspect(suffix)}Test do
      use #{inspect(web_module)}.ConnCase, async: true

      import Phoenix.LiveViewTest

      test "renders the page", %{conn: conn} do
        {:ok, view, _html} = live(conn, ~p"#{path}")

        assert has_element?(view, "##{dom_id(suffix)}")
      end
    end
    """
  end
end
