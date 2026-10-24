defmodule HeexSvelte.Source do
  @moduledoc """
  Finds the function components marked `@svelte true` in a module's source
  file.

  A marked component that is one `def` or `defp` clause whose whole body is
  a `~H` template gets its `:template`, so the template is everything it
  renders. Any other marked component, such as one with logic before its
  template or many clauses, gets a `:hand_written` reason instead: its
  `.svelte` file is written by hand, and kept in step by `:code`, the
  source of all its clauses.

  Attrs and slots come from the module's `__components__/0`, which
  Phoenix.Component builds from the `attr` and `slot` declarations. A
  component without any has none.
  """

  defstruct [:module, :function, :file, :line, :template, :first_line, :spec, :code, :hand_written]

  @doc """
  Returns `{components, errors}` for `module`, each error a map of `:file`,
  `:line` and `:message`.
  """
  def components(module) do
    file = module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()

    with {:ok, quoted} <- File.read!(file) |> Code.string_to_quoted(file: file),
         {:ok, body} <- module_body(quoted, module) do
      body
      |> statements()
      |> marked_defs()
      |> Enum.map(&component(&1, module, file))
      |> Enum.split_with(&match?(%__MODULE__{}, &1))
    else
      _ -> {[], []}
    end
  end

  # Finds `defmodule` for `module`, nested ones included: `defmodule B`
  # inside `defmodule A` defines `A.B`, as in Elixir
  defp module_body(quoted, module, parent \\ nil) do
    quoted
    |> statements()
    |> Enum.find_value(:error, fn
      {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} ->
        name = if parent, do: Module.concat([parent | parts]), else: Module.concat(parts)
        if name == module, do: {:ok, body}, else: with(:error <- module_body(body, module, name), do: nil)

      _statement ->
        nil
    end)
  end

  defp statements({:__block__, _, statements}), do: statements
  defp statements(statement), do: [statement]

  # Pairs each `@svelte true` with the next def, keeping the defs that
  # follow it with the same name to report a component with many clauses
  defp marked_defs(statements) do
    {marked, _pending} =
      Enum.reduce(statements, {[], false}, fn statement, {marked, pending} ->
        case {statement, def_name(statement), marked} do
          {{:@, _, [{:svelte, _, [true]}]}, _, _} ->
            {marked, true}

          {_, nil, _} ->
            {marked, pending}

          {_, name, _} when pending ->
            {[{name, [statement]} | marked], false}

          {_, name, [{name, defs} | rest]} ->
            {[{name, [statement | defs]} | rest], false}

          _ ->
            {marked, false}
        end
      end)

    Enum.reverse(marked)
  end

  defp def_name({kind, _, [head | _]}) when kind in [:def, :defp] do
    case head do
      {:when, _, [{name, _, _} | _]} -> name
      {name, _, _} -> name
    end
  end

  defp def_name(_statement), do: nil

  # `defs` are the component's clauses, last first
  defp component({function, defs}, module, file) do
    {_kind, meta, _} = List.last(defs)
    line = meta[:line]

    with :ok <- arity_one(defs) do
      spec = Map.get(module.__components__(), function, %{attrs: [], slots: []})

      component = %__MODULE__{
        module: module,
        function: function,
        file: file,
        line: line,
        spec: spec,
        code: defs |> Enum.reverse() |> Enum.map_join("\n", &Macro.to_string/1)
      }

      case template(defs) do
        {:ok, template, first_line} -> %{component | template: template, first_line: first_line}
        {:error, reason} -> %{component | hand_written: reason}
      end
    else
      {:error, message} -> %{file: file, line: line, message: "#{function}/1: #{message}"}
    end
  end

  defp arity_one(defs) do
    if Enum.all?(defs, fn {_kind, _, [head | _]} ->
         match?({_, _, [_]}, head) or match?({:when, _, [{_, _, [_]} | _]}, head)
       end) do
      :ok
    else
      {:error, "a component takes one argument, assigns"}
    end
  end

  defp template([{_kind, _, [_head, [do: {:sigil_H, meta, [{:<<>>, _, [template]}, []]}]]}])
       when is_binary(template) do
    first_line = if meta[:delimiter] == ~s("""), do: meta[:line] + 1, else: meta[:line]
    {:ok, template, first_line}
  end

  defp template([_def]), do: {:error, "its body is more than a single ~H template"}
  defp template(_defs), do: {:error, "it has more than one clause"}
end
