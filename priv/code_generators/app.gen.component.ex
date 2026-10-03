defmodule Mix.Tasks.App.Gen.Component do
  @shortdoc "Adds a function component to the CoreComponents module"

  @example "mix app.gen.component card"

  @moduledoc """
  #{@shortdoc}. Use it when a piece of UI is needed in more than one place,
  instead of adding the function by hand.

      $ #{@example}

  Appends the component to the end of `CoreComponents` with a doc, a `class`
  attribute, the global attributes and the inner block, so every component
  starts from the same shape:

      attr :class, :any, default: nil
      attr :rest, :global
      slot :inner_block, required: true

      def card(assigns) do
        ~H\"\"\"
        <div class={@class} {@rest}>
          {render_slot(@inner_block)}
        </div>
        \"\"\"
      end

  The name must be lower case letters, digits and underscores, like a
  function name. When it is also an HTML tag, such as `p` or `table`, the
  component tags check starts requiring `<.p>` in place of `<p>` in every
  template. Run `mix check` after generating to see what to convert.

  The task fails, and changes nothing, when a function with that name already
  exists in the module. Pass `--dry-run` to print the changes without
  writing them and `--yes` to skip the confirmation. See
  `priv/code_generators/README.md` for how the generators work and how to
  add one.
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :app,
      example: @example,
      positional: [:name]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    %{name: name} = igniter.args.positional
    web_module = Igniter.Libs.Phoenix.web_module(igniter)
    module = Module.concat(web_module, CoreComponents)

    # The task runs once in a shell and exits, so one atom from a validated
    # argument is fine here. It would not be in a long running process.
    if name =~ ~r/^[a-z][a-z0-9_]*$/ do
      add_component(igniter, module, String.to_atom(name))
    else
      Igniter.add_issue(
        igniter,
        "#{inspect(name)} is not a valid component name, use lower case letters, digits and underscores."
      )
    end
  end

  defp add_component(igniter, module, name) do
    case Igniter.Project.Module.find_and_update_module(igniter, module, &append(&1, module, name)) do
      {:ok, igniter} -> igniter
      {:error, igniter} -> Igniter.add_issue(igniter, "Could not find #{inspect(module)}.")
    end
  end

  # The zipper is at the body of the module, so the code goes after the
  # last definition.
  defp append(zipper, module, name) do
    case Igniter.Code.Function.move_to_def(zipper, name, 1) do
      {:ok, _zipper} -> {:error, "#{inspect(module)} already defines #{name}/1."}
      :error -> {:ok, Igniter.Code.Common.add_code(zipper, component(name))}
    end
  end

  defp component(name) do
    """
    @doc \"\"\"
    Renders a #{String.replace(to_string(name), "_", " ")}.

    ## Examples

        <.#{name}>Content</.#{name}>
    \"\"\"
    attr :class, :any, default: nil
    attr :rest, :global
    slot :inner_block, required: true

    def #{name}(assigns) do
      ~H\"\"\"
      <div class={@class} {@rest}>
        {render_slot(@inner_block)}
      </div>
      \"\"\"
    end
    """
  end
end
