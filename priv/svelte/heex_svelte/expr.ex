defmodule HeexSvelte.Expr do
  @moduledoc """
  Translates the small part of Elixir a mirrored template may use into
  JavaScript. Anything outside that part throws `{:heex_svelte, line,
  message}`, so the build reports it instead of guessing.

  Supported: `@assign`, loop and `:let` variables, `a.b`, `a[:b]`,
  literals, lists, string interpolation, `if/2` with `do:` and `else:`,
  `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!`, `and`, `or`, `not`,
  `+`, `-`, `*`, `/` and `<>`. Comparing an assign with `[]` is a check for
  an empty list, or for a missing slot when the assign is a slot.

  The JavaScript keeps JavaScript's truthiness: `0` and `""` are false,
  where in Elixir only `nil` and `false` are.
  """

  @reserved ~w(
    await break case catch class const continue debugger default delete do else enum
    export extends false finally for function if implements import in instanceof
    interface let new null package private protected public return static super switch
    this throw true try typeof var void while with yield
  )

  @binary_ops %{
    ==: "===",
    !=: "!==",
    ===: "===",
    !==: "!==",
    <: "<",
    >: ">",
    <=: "<=",
    >=: ">=",
    &&: "&&",
    ||: "||",
    and: "&&",
    or: "||",
    +: "+",
    -: "-",
    *: "*",
    /: "/",
    <>: "+"
  }

  @doc """
  The JavaScript name for an Elixir assign or variable name. A JavaScript
  reserved word, such as `class`, gets a trailing underscore.
  """
  def js_name(name) do
    name = to_string(name)

    cond do
      name in @reserved -> name <> "_"
      Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, name) -> name
      true -> throw({:heex_svelte, nil, "#{name} is not a valid JavaScript name"})
    end
  end

  @doc """
  Parses `code` and translates it. `ctx` holds the declared `:attrs` and
  `:slots` and the `:locals` in scope, each a list of atoms, and the `:line`
  the code starts on.
  """
  def translate(code, ctx) do
    code
    |> parse(ctx.line)
    |> to_js(ctx)
  end

  @doc "Parses `code` into quoted Elixir, throwing on a syntax error."
  def parse(code, line) do
    case Code.string_to_quoted(code, line: line || 1) do
      {:ok, quoted} -> quoted
      {:error, {meta, message, token}} -> throw({:heex_svelte, line_of(meta, line), "#{message}#{token}"})
    end
  end

  @doc "Translates quoted Elixir."
  def to_js(quoted, ctx)

  def to_js({:@, meta, [{name, _, context}]}, ctx) when is_atom(name) and is_atom(context) do
    cond do
      name == :inner_block -> unsupported(meta, ctx, "@inner_block outside render_slot/1")
      name in ctx.slots -> unsupported(meta, ctx, "@#{name} outside render_slot/1")
      name in ctx.attrs -> js_name(name)
      true -> unsupported(meta, ctx, "@#{name}, which is not a declared attr or slot")
    end
  end

  def to_js({name, meta, context}, ctx) when is_atom(name) and is_atom(context) do
    if name in ctx.locals do
      js_name(name)
    else
      unsupported(meta, ctx, "the variable #{name}, which no :for, for or :let defines")
    end
  end

  # Slots are lists in Elixir and an optional snippet in Svelte
  def to_js({op, _meta, [{:@, _, [{name, _, _}]}, []]}, ctx) when op in [:==, :!=] do
    cond do
      name in ctx.slots ->
        if op == :!=, do: "#{slot_js_name(name)} != null", else: "#{slot_js_name(name)} == null"

      name in ctx.attrs ->
        if op == :!=, do: "#{js_name(name)}.length > 0", else: "#{js_name(name)}.length === 0"

      true ->
        unsupported([], ctx, "@#{name}, which is not a declared attr or slot")
    end
  end

  def to_js({:if, meta, [condition, clauses]}, ctx) when is_list(clauses) do
    if Keyword.keys(clauses) -- [:do, :else] != [] or not Keyword.has_key?(clauses, :do) do
      unsupported(meta, ctx, "if/2 without keyword do: and else:")
    end

    then = to_js(Keyword.fetch!(clauses, :do), ctx)
    otherwise = clauses |> Keyword.get(:else) |> to_js(ctx)
    "(#{to_js(condition, ctx)} ? #{then} : #{otherwise})"
  end

  def to_js({op, meta, [left, right]}, ctx) when is_map_key(@binary_ops, op) do
    if op in [:==, :!=, :===, :!==] and (collection?(left) or collection?(right)) do
      unsupported(meta, ctx, "#{op} with a list or map, which JavaScript compares by reference")
    end

    "#{operand(left, ctx)} #{Map.fetch!(@binary_ops, op)} #{operand(right, ctx)}"
  end

  def to_js({op, _meta, [value]}, ctx) when op in [:!, :not] do
    "!" <> operand(value, ctx)
  end

  def to_js({:-, _meta, [value]}, ctx), do: "-" <> operand(value, ctx)

  # a.b
  def to_js({{:., _, [left, field]}, meta, []}, ctx) when is_atom(field) do
    if Keyword.get(meta, :no_parens) do
      "#{to_js(left, ctx)}.#{field}"
    else
      unsupported(meta, ctx, "the call #{Macro.to_string(left)}.#{field}()")
    end
  end

  # a[:b]
  def to_js({{:., _, [Access, :get]}, _meta, [left, key]}, ctx) do
    "#{to_js(left, ctx)}[#{to_js(key, ctx)}]"
  end

  # "a #{b}"
  def to_js({:<<>>, _meta, parts}, ctx) do
    inner =
      Enum.map_join(parts, fn
        part when is_binary(part) ->
          part |> String.replace("\\", "\\\\") |> String.replace("`", "\\`") |> String.replace("${", "\\${")

        {:"::", _, [{{:., _, [Kernel, :to_string]}, _, [value]}, {:binary, _, _}]} ->
          "${#{to_js(value, ctx)}}"
      end)

    "`" <> inner <> "`"
  end

  def to_js(list, ctx) when is_list(list) do
    if Keyword.keyword?(list) and list != [] do
      unsupported([], ctx, "a keyword list")
    end

    "[" <> Enum.map_join(list, ", ", &to_js(&1, ctx)) <> "]"
  end

  def to_js(nil, _ctx), do: "null"
  def to_js(boolean, _ctx) when is_boolean(boolean), do: to_string(boolean)
  def to_js(atom, _ctx) when is_atom(atom), do: Jason.encode!(Atom.to_string(atom))
  def to_js(string, _ctx) when is_binary(string), do: Jason.encode!(string)
  def to_js(number, _ctx) when is_number(number), do: to_string(number)

  def to_js({call, meta, args}, ctx) when is_list(args) do
    unsupported(meta, ctx, "the call #{Macro.to_string({call, [], args})}")
  end

  def to_js(other, ctx) do
    unsupported([], ctx, Macro.to_string(other))
  end

  @doc "Translates a constant, like an attr's default, into a JavaScript literal."
  def literal(value) when is_list(value), do: "[" <> Enum.map_join(value, ", ", &literal/1) <> "]"
  def literal(value) when is_map(value) and not is_struct(value), do: Jason.encode!(value)
  def literal(value) when is_atom(value) or is_binary(value) or is_number(value), do: to_js(value, %{})

  def literal(value) do
    throw({:heex_svelte, nil, "the default #{inspect(value)}, which has no JavaScript form"})
  end

  @doc "The JavaScript name of a slot: `inner_block` is Svelte's `children`."
  def slot_js_name(:inner_block), do: "children"
  def slot_js_name(name), do: js_name(name)

  defp operand({op, _, [_, _]} = quoted, ctx) when is_map_key(@binary_ops, op) do
    "(" <> to_js(quoted, ctx) <> ")"
  end

  defp operand({:if, _, [_, _]} = quoted, ctx), do: to_js(quoted, ctx)
  defp operand(quoted, ctx), do: to_js(quoted, ctx)

  defp collection?([]), do: false
  defp collection?(list) when is_list(list), do: true
  defp collection?({:%{}, _, _}), do: true
  defp collection?(_), do: false

  defp unsupported(meta, ctx, what) do
    throw({:heex_svelte, line_of(meta, ctx[:line]), "unsupported: #{what}"})
  end

  defp line_of(meta, default) when is_list(meta), do: Keyword.get(meta, :line, default)
  defp line_of(_meta, default), do: default
end
