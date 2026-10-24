defmodule HeexSvelte.SourceTest do
  use ExUnit.Case, async: true

  alias HeexSvelte.Source

  defmodule Components do
    use Phoenix.Component

    Module.register_attribute(__MODULE__, :svelte, accumulate: true)

    @svelte true
    attr :title, :string, required: true

    def plain(assigns) do
      ~H"""
      <p>{@title}</p>
      """
    end

    @svelte true
    def no_declarations(assigns) do
      ~H"<hr />"
    end

    @svelte true
    attr :variant, :string, default: nil

    def with_logic(assigns) do
      assigns = assign(assigns, :class, "btn")

      ~H"""
      <button class={@class}>{@variant}</button>
      """
    end

    @svelte true
    attr :kind, :atom, required: true

    def clauses(%{kind: :a} = assigns), do: ~H"<b>a</b>"
    def clauses(assigns), do: ~H"<i>b</i>"

    def unmarked(assigns), do: ~H"<p></p>"
  end

  setup_all do
    {components, errors} = Source.components(Components)
    %{components: Map.new(components, &{&1.function, &1}), errors: errors}
  end

  test "finds only the marked components", %{components: components, errors: errors} do
    assert components |> Map.keys() |> Enum.sort() == [:clauses, :no_declarations, :plain, :with_logic]
    assert errors == []
  end

  test "takes the template of a single ~H clause and its first line", %{components: components} do
    assert %Source{template: "<p>{@title}</p>\n", first_line: 16, hand_written: nil} = components.plain
    assert [%{name: :title}] = components.plain.spec.attrs
  end

  test "gives a component without attrs or slots none", %{components: components} do
    assert %Source{template: "<hr />", spec: %{attrs: [], slots: []}} = components.no_declarations
  end

  test "asks for a file by hand for logic before the template or many clauses", %{components: components} do
    assert %Source{template: nil, hand_written: "its body is more than a single ~H template"} =
             components.with_logic

    assert components.with_logic.code =~ ~s|assign(assigns, :class, "btn")|

    assert %Source{template: nil, hand_written: "it has more than one clause"} = components.clauses
    assert components.clauses.code =~ ~s|<b>a</b>|
    assert components.clauses.code =~ ~s|<i>b</i>|
  end
end
