defmodule Mix.Tasks.App.Gen.ComponentTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  # The project built by `test_project/1` is called `:test`, so its web
  # module is `TestWeb`. A components module with one component is enough
  # for the generator to append to and to refuse to duplicate. The project
  # carries this repository's `.formatter.exs`, so the written code is
  # formatted the same way.
  @core_components """
  defmodule TestWeb.CoreComponents do
    use Phoenix.Component

    attr :rest, :global
    slot :inner_block, required: true

    def button(assigns) do
      ~H\"\"\"
      <button {@rest}>{render_slot(@inner_block)}</button>
      \"\"\"
    end
  end
  """

  defp project do
    test_project(
      files: %{
        ".formatter.exs" => File.read!(".formatter.exs"),
        "lib/test_web/components/core_components.ex" => @core_components
      }
    )
  end

  defp generate(igniter, name) do
    Igniter.compose_task(igniter, "app.gen.component", [name])
  end

  test "appends the component to the end of the module" do
    project()
    |> generate("card")
    |> assert_has_patch("lib/test_web/components/core_components.ex", """
    + |  @doc \"\"\"
    + |  Renders a card.
    + |
    + |  ## Examples
    + |
    + |      <.card>Content</.card>
    + |  \"\"\"
    + |  attr :class, :any, default: nil
    + |  attr :rest, :global
    + |  slot :inner_block, required: true
    + |
    + |  def card(assigns) do
    + |    ~H\"\"\"
    + |    <div class={@class} {@rest}>
    + |      {render_slot(@inner_block)}
    + |    </div>
    + |    \"\"\"
    + |  end
      |end
    """)
  end

  test "refuses a name that is not a function name" do
    project()
    |> generate("Card")
    |> assert_has_issue(&(&1 =~ ~s("Card" is not a valid component name)))
    |> assert_unchanged("lib/test_web/components/core_components.ex")
  end

  test "refuses when the module already defines the component" do
    project()
    |> generate("button")
    |> assert_has_issue(&(&1 =~ "TestWeb.CoreComponents already defines button/1"))
    |> assert_unchanged("lib/test_web/components/core_components.ex")
  end

  test "refuses when there is no components module" do
    test_project()
    |> generate("card")
    |> assert_has_issue(&(&1 =~ "Could not find TestWeb.CoreComponents"))
  end
end
