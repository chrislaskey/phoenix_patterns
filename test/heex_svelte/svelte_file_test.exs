defmodule HeexSvelte.SvelteFileTest do
  use ExUnit.Case, async: true

  alias HeexSvelte.{Source, SvelteFile}

  @moduletag :tmp_dir

  defp component(tmp_dir, template) do
    %Source{
      module: Example.Components,
      function: :status_card,
      file: Path.join(tmp_dir, "components.ex"),
      line: 1,
      template: template,
      first_line: 2,
      spec: %{
        attrs: [
          %{name: :title, type: :string, required: true, opts: [], line: 3, doc: nil, slot: nil},
          %{
            name: :variant,
            type: :string,
            required: false,
            opts: [values: ~w(info warn), default: "info"],
            doc: nil
          }
        ],
        slots: [%{name: :inner_block, required: false, opts: [], attrs: [], line: 5, doc: nil}]
      }
    }
  end

  test "writes the file next to the component with props and a header", %{tmp_dir: tmp_dir} do
    component = component(tmp_dir, ~s|<div class={@variant}>{@title} {render_slot(@inner_block)}</div>\n|)

    assert [{:written, path}] = HeexSvelte.build([component])
    assert path == Path.join(tmp_dir, "StatusCard.svelte")

    contents = File.read!(path)
    assert contents =~ "from Example.Components.status_card/1"
    assert contents =~ ~s(@property {"info" | "warn"} [variant])
    assert contents =~ ~s|@property {import("svelte").Snippet<[]>} [children]|
    assert contents =~ ~s|let { title, variant = "info", children } = $props()|
    assert contents =~ "<div class={variant}>{title} {@render children?.()}</div>\n"

    assert HeexSvelte.check([component]) == []
    assert HeexSvelte.build([component]) == [{:unchanged, path}]
  end

  test "reports a generated file as stale and regenerates it", %{tmp_dir: tmp_dir} do
    [{:written, path}] = HeexSvelte.build([component(tmp_dir, "<p>{@title}</p>")])
    changed = component(tmp_dir, "<h2>{@title}</h2>")

    assert HeexSvelte.check([changed]) == [{:stale, path}]
    assert HeexSvelte.build([changed]) == [{:written, path}]
    assert File.read!(path) =~ "<h2>{title}</h2>"
    assert HeexSvelte.check([changed]) == []
  end

  test "keeps a file edited by hand until it is accepted or forced", %{tmp_dir: tmp_dir} do
    original = component(tmp_dir, "<p>{@title}</p>")
    [{:written, path}] = HeexSvelte.build([original])
    File.write!(path, String.replace(File.read!(path), "<p>{title}</p>", "<p class=\"custom\">{title}</p>"))

    assert HeexSvelte.build([original]) == [{:edited, path}]

    changed = component(tmp_dir, "<p class=\"lead\">{@title}</p>")
    assert HeexSvelte.check([changed]) == [{:stale, path}]
    assert HeexSvelte.build([changed]) == [{:stale_edit, path}]
    assert File.read!(path) =~ "custom"

    assert HeexSvelte.accept([changed], [path]) == [:ok]
    assert HeexSvelte.check([changed]) == []
    assert HeexSvelte.build([changed]) == [{:edited, path}]
    assert File.read!(path) =~ "custom"

    assert HeexSvelte.build([changed], force: true) == [{:written, path}]
    assert File.read!(path) =~ ~s(<p class="lead">{title}</p>)
  end

  test "adopts a file written by hand from the start", %{tmp_dir: tmp_dir} do
    component = component(tmp_dir, "<p>{@title}</p>")
    path = SvelteFile.path(component)
    File.write!(path, "<p>written by hand</p>\n")

    assert HeexSvelte.build([component]) == [{:no_header, path}]
    assert HeexSvelte.check([component]) == [{:no_header, path}]

    assert HeexSvelte.accept([component], [path]) == [:ok]
    assert {:ok, %{output: "none", edited?: true, body: "<p>written by hand</p>\n"}} = SvelteFile.read(path)
    assert HeexSvelte.check([component]) == []
  end

  test "reports a template it cannot mirror without writing", %{tmp_dir: tmp_dir} do
    component = component(tmp_dir, "<p>\n  {Enum.count(@title)}\n</p>")

    assert [{:error, %{line: 3, message: "Example.Components.status_card/1: unsupported: " <> _}}] =
             HeexSvelte.build([component])

    refute File.exists?(SvelteFile.path(component))
  end

  test "leaves out props for a component without attrs or slots", %{tmp_dir: tmp_dir} do
    component = %{component(tmp_dir, "<hr />") | spec: %{attrs: [], slots: []}}

    [{:written, path}] = HeexSvelte.build([component])

    assert File.read!(path) =~ ~r/<script>\n<\/script>\n\n<hr \/>\n\z/
  end

  describe "a component that can't be generated" do
    defp hand_written(tmp_dir, code) do
      %{component(tmp_dir, nil) | code: code, hand_written: "its body is more than a single ~H template"}
    end

    test "asks for its file to be written by hand", %{tmp_dir: tmp_dir} do
      component = hand_written(tmp_dir, "def status_card(assigns), do: ...")
      path = SvelteFile.path(component)

      problem =
        {:hand_write,
         %{path: path, component: "Example.Components.status_card/1", reason: component.hand_written}}

      assert HeexSvelte.build([component]) == [problem]
      assert HeexSvelte.build([component], force: true) == [problem]
      assert HeexSvelte.check([component]) == [problem]
      assert HeexSvelte.describe(problem) =~ "Write #{path} by hand"
      refute File.exists?(path)
    end

    test "follows the whole component once written and accepted", %{tmp_dir: tmp_dir} do
      component = hand_written(tmp_dir, "def status_card(assigns), do: ...")
      path = SvelteFile.path(component)
      File.write!(path, "<p>by hand</p>\n")

      assert HeexSvelte.accept([component], [path]) == [:ok]
      assert File.read!(path) =~ "Written by hand to mirror Example.Components.status_card/1"
      assert HeexSvelte.check([component]) == []
      assert HeexSvelte.build([component], force: true) == [{:edited, path}]

      changed = hand_written(tmp_dir, "def status_card(assigns), do: ... # changed")
      assert HeexSvelte.check([changed]) == [{:stale, path}]
      assert HeexSvelte.build([changed], force: true) == [{:stale_edit, path}]
      assert File.read!(path) =~ "<p>by hand</p>"
    end
  end
end
