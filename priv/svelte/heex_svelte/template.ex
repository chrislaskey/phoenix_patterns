defmodule HeexSvelte.Template do
  @moduledoc """
  Translates a HEEx template into Svelte markup.

  The template is parsed with LiveView's own parser, the one
  `mix format` uses, so it reads HEEx exactly as LiveView does. The parser
  is internal to LiveView, which is why `test/heex_svelte` covers every
  construct below: a LiveView upgrade that changes it fails those tests.

  Supported:

    * HTML tags, text, `{expr}`, `<%= expr %>` and `<%!-- comments --%>`
    * `<%= if %>`, `<%= unless %>`, `<%= for x <- xs %>` and `<%= cond %>`
      blocks, and the `:if`, `:for` and `:key` attributes
    * `{@rest}` on a tag or component, as `{...rest}`
    * `render_slot(@inner_block)` and named slots, with one optional argument
    * `<.component>` and `<Module.component>` calls to other components
      marked `@svelte`, with `<:slot>` entries that have only a `:let`
    * `phx-click`, `phx-submit` and `phx-change`, which call the `emit`
      function from Svelte context instead of LiveView. `phx-value-*`
      attributes become the click payload. `phx-target`, `phx-disable-with`,
      `phx-debounce`, `phx-throttle` and `phx-no-curly-interpolation` are
      dropped, since they mean nothing outside LiveView
    * `phx-click={JS.dispatch("name")}`, with optional `detail:` and
      `bubbles:`, which dispatches the same DOM event LiveView would

  Everything else, including other `phx-*` attributes, other `JS` commands, `<% %>` without
  `=`, `case`, `<.link>`, `<.form>` and colocated scripts, throws
  `{:heex_svelte, line, message}`.
  """

  alias HeexSvelte.Expr
  alias Phoenix.LiveView.TagEngine.Parser

  @events %{"phx-click" => "onclick", "phx-submit" => "onsubmit", "phx-change" => "oninput"}
  @dropped ~w(phx-target phx-disable-with phx-debounce phx-throttle phx-no-curly-interpolation phx-page-loading)

  @doc """
  Translates `source`. `ctx` holds the component's `:attrs` and `:slots`,
  the `:first_line` of the template in its file, and `:resolve`, a
  function that turns a component call into `{:ok, svelte_name, target}`
  or `:error`.

  Returns `{markup, uses}` where `uses` lists `{:component, name, target}` for each
  component it calls, `{:render_slot, slot, arity}` for each way it renders
  a slot, and `:emit` when it calls the event function.
  """
  def translate(source, ctx) do
    nodes =
      case Parser.parse(source,
             tag_handler: Phoenix.LiveView.HTMLEngine,
             file: "nofile",
             skip_macro_components: true,
             prune_text_after_slots: false,
             trim_eex: true
           ) do
        {:ok, %{nodes: nodes}} -> nodes
        {:error, line, _column, message} -> throw({:heex_svelte, file_line(line, ctx), message})
      end

    ctx = Map.merge(%{locals: [], line: ctx[:first_line] || 1}, ctx)
    Process.put(:heex_svelte_uses, [])
    markup = nodes(nodes, ctx)
    {IO.iodata_to_binary(markup), Process.get(:heex_svelte_uses) |> Enum.reverse() |> Enum.uniq()}
  after
    Process.delete(:heex_svelte_uses)
  end

  defp nodes(nodes, ctx), do: Enum.map(nodes, &node(&1, ctx))

  defp node({:text, text, _meta}, _ctx), do: escape_text(text)

  defp node({:eex_comment, text}, _ctx), do: ["<!--", text, "-->"]

  defp node({:body_expr, code, meta}, ctx), do: output(code, at(ctx, meta))
  defp node({:eex, code, %{opt: ~c"="} = meta}, ctx), do: output(code, at(ctx, meta))

  defp node({:eex, code, meta}, ctx) do
    throw({:heex_svelte, line(ctx, meta), "unsupported: <% #{code} %>, which renders nothing"})
  end

  defp node({:eex_block, expr, clauses, meta}, ctx), do: block(expr, clauses, at(ctx, meta))

  defp node({:block, type, name, attrs, children, meta, _close}, ctx) do
    element(type, name, attrs, children, at(ctx, meta))
  end

  defp node({:self_close, type, name, attrs, meta}, ctx) do
    element(type, name, attrs, :self_close, at(ctx, meta))
  end

  # {expr} and <%= expr %>

  defp output(code, ctx) do
    case Expr.parse(code, ctx.line) do
      {:render_slot, _, [{:@, _, [{slot, _, _}]} | args]} when length(args) <= 1 ->
        if slot not in ctx.slots do
          throw(
            {:heex_svelte, ctx.line, "unsupported: render_slot of @#{slot}, which is not a declared slot"}
          )
        end

        Process.put(:heex_svelte_uses, [{:render_slot, slot, length(args)} | Process.get(:heex_svelte_uses)])
        ["{@render ", Expr.slot_js_name(slot), "?.(", Enum.map_join(args, &Expr.to_js(&1, ctx)), ")}"]

      {:render_slot, _, _} ->
        throw(
          {:heex_svelte, ctx.line,
           "unsupported: render_slot of anything but @slot, or with more than one argument"}
        )

      quoted ->
        ["{", Expr.to_js(quoted, ctx), "}"]
    end
  end

  # <%= if %>, <%= unless %>, <%= for %> and <%= cond %>

  defp block("cond do", [{leading, _, _} | _] = clauses, ctx) do
    if not blank?(leading),
      do: throw({:heex_svelte, ctx.line, "unsupported: content before the first cond clause"})

    branches =
      clauses
      |> Enum.zip(tl(clauses))
      |> Enum.map(fn {{_, condition, meta}, {children, _, _}} ->
        condition = condition |> String.trim() |> String.trim_trailing("->") |> String.trim()
        {condition, children, at(ctx, meta)}
      end)

    branches
    |> Enum.with_index()
    |> Enum.map(fn {{condition, children, ctx}, index} ->
      tag =
        cond do
          condition == "true" and index > 0 -> "{:else}"
          index == 0 -> ["{#if ", Expr.translate(condition, ctx), "}"]
          true -> ["{:else if ", Expr.translate(condition, ctx), "}"]
        end

      [tag, nodes(children, ctx)]
    end)
    |> then(&[&1, "{/if}"])
  end

  defp block(expr, clauses, ctx) do
    case Expr.parse(expr <> "\nnil\nend", ctx.line) do
      {:if, _, [condition, [do: _]]} ->
        if_block(Expr.to_js(condition, ctx), clauses, ctx)

      {:unless, _, [condition, [do: _]]} ->
        if_block("!(#{Expr.to_js(condition, ctx)})", clauses, ctx)

      {:for, _, [{:<-, _, [pattern, collection]}, [do: _]]} ->
        each_block(pattern, collection, nil, clauses, ctx)

      _ ->
        throw({:heex_svelte, ctx.line, "unsupported: the block <%= #{expr} %>"})
    end
  end

  defp if_block(condition, [{children, "end", _}], ctx) do
    ["{#if ", condition, "}", nodes(children, ctx), "{/if}"]
  end

  defp if_block(condition, [{children, "else", _}, {else_children, "end", _}], ctx) do
    ["{#if ", condition, "}", nodes(children, ctx), "{:else}", nodes(else_children, ctx), "{/if}"]
  end

  defp if_block(_condition, _clauses, ctx) do
    throw({:heex_svelte, ctx.line, "unsupported: an if block with clauses other than else"})
  end

  defp each_block(pattern, collection, key, [{children, "end", _}], ctx) do
    each(pattern, collection, key, ctx, &nodes(children, &1))
  end

  defp each_block(_pattern, _collection, _key, _clauses, ctx) do
    throw({:heex_svelte, ctx.line, "unsupported: a for block with more than one clause"})
  end

  defp each(pattern, collection, key, ctx, inner) do
    name =
      case pattern do
        {name, _, context} when is_atom(name) and is_atom(context) -> name
        _ -> throw({:heex_svelte, ctx.line, "unsupported: the for pattern #{Macro.to_string(pattern)}"})
      end

    collection = Expr.to_js(collection, ctx)
    inner_ctx = %{ctx | locals: [name | ctx.locals]}
    key = if key, do: [" (", Expr.translate(key, inner_ctx), ")"], else: []

    ["{#each ", collection, " as ", Expr.js_name(name), key, "}", inner.(inner_ctx), "{/each}"]
  end

  # Tags, components and slots, wrapped in :for and :if

  defp element(type, name, attrs, children, ctx) do
    {special, attrs} = Enum.split_with(attrs, fn {attr, _, _} -> attr in [":if", ":for", ":key"] end)
    special = Map.new(special, fn {attr, value, meta} -> {attr, {expr!(attr, value, ctx), at(ctx, meta)}} end)

    render_if = fn ctx ->
      case special[":if"] do
        nil ->
          plain_element(type, name, attrs, children, ctx)

        {code, _} ->
          ["{#if ", Expr.translate(code, ctx), "}", plain_element(type, name, attrs, children, ctx), "{/if}"]
      end
    end

    case special[":for"] do
      nil ->
        render_if.(ctx)

      {code, for_ctx} ->
        case Expr.parse(code, for_ctx.line) do
          {:<-, _, [pattern, collection]} ->
            key = with {key, _} <- special[":key"], do: key
            each(pattern, collection, key, ctx, render_if)

          _ ->
            throw({:heex_svelte, for_ctx.line, "unsupported: :for={#{code}}"})
        end
    end
  end

  defp plain_element(:tag, name, _attrs, _children, ctx) when name in ["script", "style"] do
    throw({:heex_svelte, ctx.line, "unsupported: a <#{name}> tag"})
  end

  defp plain_element(:tag, name, attrs, children, ctx) do
    open = ["<", name, tag_attrs(name, attrs, ctx)]

    case children do
      :self_close ->
        if Phoenix.LiveView.HTMLEngine.void?(name), do: [open, " />"], else: [open, "></", name, ">"]

      children ->
        [open, ">", nodes(children, ctx), "</", name, ">"]
    end
  end

  defp plain_element(type, name, attrs, children, ctx) when type in [:local_component, :remote_component] do
    tag_name = if type == :local_component, do: "." <> name, else: name

    {component, target} =
      case ctx.resolve.(type, name) do
        {:ok, component, target} ->
          {component, target}

        :error ->
          throw(
            {:heex_svelte, ctx.line, "unsupported: <#{tag_name}>, which is not a component marked @svelte"}
          )
      end

    Process.put(:heex_svelte_uses, [{:component, component, target} | Process.get(:heex_svelte_uses)])

    {lets, attrs} = Enum.split_with(attrs, fn {attr, _, _} -> attr == ":let" end)
    open = ["<", component, tag_attrs(nil, attrs, ctx)]

    case children do
      :self_close -> [open, " />"]
      children -> [open, ">", component_children(children, lets, ctx), "</", component, ">"]
    end
  end

  defp plain_element(:slot, name, _attrs, _children, ctx) do
    throw({:heex_svelte, ctx.line, "unsupported: <:#{name}> outside a component"})
  end

  defp component_children(children, lets, ctx) do
    {slots, default} = Enum.split_with(children, &match?({:block, :slot, _, _, _, _, _}, &1))

    snippets =
      Enum.map(slots, fn {:block, :slot, name, attrs, slot_children, meta, _} ->
        {lets, others} = Enum.split_with(attrs, fn {attr, _, _} -> attr == ":let" end)
        ctx = at(ctx, meta)
        if others != [], do: throw({:heex_svelte, ctx.line, "unsupported: attributes on <:#{name}>"})
        snippet(name, lets, slot_children, ctx)
      end)

    default =
      case lets do
        [] -> nodes(default, ctx)
        lets -> snippet("children", lets, default, ctx)
      end

    [snippets, default]
  end

  defp snippet(name, lets, children, ctx) do
    {param, ctx} =
      case lets do
        [] ->
          {"", ctx}

        [{":let", value, meta}] ->
          case Expr.parse(expr!(":let", value, ctx), line(ctx, meta)) do
            {var, _, context} when is_atom(var) and is_atom(context) ->
              {Expr.js_name(var), %{ctx | locals: [var | ctx.locals]}}

            other ->
              throw({:heex_svelte, line(ctx, meta), "unsupported: :let={#{Macro.to_string(other)}}"})
          end
      end

    ["{#snippet ", name, "(", param, ")}", nodes(children, ctx), "{/snippet}"]
  end

  # Attributes

  # `tag` is nil for a component, which gets event attributes as props like
  # `onclick` that its `{...rest}` passes on
  defp tag_attrs(tag, attrs, ctx) do
    {values, attrs} =
      Enum.split_with(attrs, fn {name, _, _} ->
        is_binary(name) and String.starts_with?(name, "phx-value-")
      end)

    Enum.map(attrs, fn
      {:root, value, meta} ->
        [" ", spread(value, at(ctx, meta))]

      {name, value, meta} when is_map_key(@events, name) ->
        [" ", event(tag, name, value, values, at(ctx, meta))]

      {name, _value, _meta} when name in @dropped ->
        []

      {"phx-" <> _ = name, _value, meta} ->
        throw({:heex_svelte, line(ctx, meta), "unsupported: the #{name} attribute"})

      {name, nil, _meta} ->
        [" ", name]

      {name, {:string, value, _}, _meta} ->
        [" ", name, "=", quote_attr(value)]

      {name, {:expr, code, _}, meta} ->
        [" ", name, "={", Expr.translate(code, at(ctx, meta)), "}"]
    end)
    |> then(fn rendered ->
      if values != [] and not Enum.any?(attrs, fn {name, _, _} -> name == "phx-click" end) do
        throw({:heex_svelte, ctx.line, "unsupported: phx-value-* without phx-click"})
      end

      rendered
    end)
  end

  defp event(tag, "phx-click", {:expr, code, _} = value, values, ctx) do
    case Expr.parse(code, ctx.line) do
      {{:., _, [{:__aliases__, _, [:JS]}, :dispatch]}, _, args} -> dispatch(args, values, ctx)
      _ -> server_event(tag, value, values, ctx)
    end
  end

  defp event(tag, "phx-click", value, values, ctx), do: server_event(tag, value, values, ctx)

  defp event(tag, name, value, _values, ctx) do
    if tag != "form", do: throw({:heex_svelte, ctx.line, "unsupported: #{name} anywhere but on a <form> tag"})
    Process.put(:heex_svelte_uses, [:emit | Process.get(:heex_svelte_uses)])
    prevent = if name == "phx-submit", do: "event.preventDefault(); ", else: ""

    [
      Map.fetch!(@events, name),
      "={(event) => { ",
      prevent,
      "emit(",
      event_name(value, ctx),
      ", new FormData(event.currentTarget), event) }}"
    ]
  end

  # JS.dispatch("name", detail: ..., bubbles: ...) dispatches the same event
  # LiveView's client does: cancelable, bubbling unless told otherwise, with
  # the clicked element as `detail.dispatcher`
  defp dispatch([name | opts], values, ctx) when is_binary(name) and name != "click" and length(opts) <= 1 do
    opts = List.first(opts, [])

    if not Keyword.keyword?(opts) or Keyword.keys(opts) -- [:detail, :bubbles] != [] do
      throw({:heex_svelte, ctx.line, "unsupported: JS.dispatch options other than detail: and bubbles:"})
    end

    if values != [] do
      throw({:heex_svelte, ctx.line, "unsupported: phx-value-* with JS.dispatch, which doesn't send them"})
    end

    bubbles =
      case Keyword.get(opts, :bubbles, true) do
        bubbles when is_boolean(bubbles) -> to_string(bubbles)
        _ -> throw({:heex_svelte, ctx.line, "unsupported: a JS.dispatch bubbles: other than true or false"})
      end

    detail =
      case Keyword.fetch(opts, :detail) do
        {:ok, {:%{}, _, pairs}} ->
          Enum.map(pairs, fn {key, value} -> "#{object_key(to_string(key))}: #{Expr.to_js(value, ctx)}, " end)

        {:ok, _} ->
          throw({:heex_svelte, ctx.line, "unsupported: a JS.dispatch detail: other than a %{} map"})

        :error ->
          []
      end

    [
      "onclick={(event) => event.currentTarget.dispatchEvent(new CustomEvent(",
      Jason.encode!(name),
      ", {bubbles: #{bubbles}, cancelable: true, detail: {",
      detail,
      "dispatcher: event.currentTarget}}))}"
    ]
  end

  defp dispatch(_args, _values, ctx) do
    throw({:heex_svelte, ctx.line, "unsupported: JS.dispatch without a string event name, or of \"click\""})
  end

  defp server_event(_tag, value, values, ctx) do
    Process.put(:heex_svelte_uses, [:emit | Process.get(:heex_svelte_uses)])

    payload =
      Enum.map_join(values, ", ", fn {"phx-value-" <> key, value, meta} ->
        value =
          case value do
            {:string, string, _} -> Jason.encode!(string)
            {:expr, code, _} -> Expr.translate(code, at(ctx, meta))
            nil -> ~s("")
          end

        "#{object_key(key)}: #{value}"
      end)

    ["onclick={(event) => emit(", event_name(value, ctx), ", {", payload, "}, event)}"]
  end

  defp event_name({:string, name, _}, _ctx), do: Jason.encode!(name)
  defp event_name({:expr, code, _}, ctx), do: Expr.translate(code, ctx)

  defp event_name(nil, ctx),
    do: throw({:heex_svelte, ctx.line, "unsupported: an event attribute without a value"})

  defp spread({:expr, code, _}, ctx) do
    case Expr.parse(code, ctx.line) do
      {:@, _, [{name, _, _}]} -> ["{...", Expr.to_js({:@, [], [{name, [], nil}]}, ctx), "}"]
      _ -> throw({:heex_svelte, ctx.line, "unsupported: {#{code}} as attributes, only {@rest}"})
    end
  end

  defp expr!(_attr, {:expr, code, _}, _ctx), do: code
  defp expr!(attr, _value, ctx), do: throw({:heex_svelte, ctx.line, "#{attr} needs an {expression}"})

  defp object_key(key) do
    if Regex.match?(~r/^[a-zA-Z_$][a-zA-Z0-9_$]*$/, key), do: key, else: Jason.encode!(key)
  end

  # HEEx writes a static attribute's text as it is, entities included, and
  # Svelte reads entities the way the browser does, so only the quote and
  # Svelte's braces need escaping. A bare `&`, as in Tailwind's
  # `[[data-theme=dark]_&]:` variants, stays as it is for class scanners
  defp quote_attr(value) do
    escaped =
      value
      |> String.replace("\"", "&quot;")
      |> String.replace("{", "&#123;")
      |> String.replace("}", "&#125;")

    [?", escaped, ?"]
  end

  defp escape_text(text) do
    text |> String.replace("{", "&#123;") |> String.replace("}", "&#125;")
  end

  defp blank?(nodes) do
    Enum.all?(nodes, fn
      {:text, text, _} -> String.trim(text) == ""
      {:eex_comment, _} -> true
      _ -> false
    end)
  end

  # Lines: parser lines count from the template's first line

  defp at(ctx, meta), do: %{ctx | line: line(ctx, meta)}

  defp line(ctx, %{line: line}), do: file_line(line, ctx)
  defp line(ctx, _meta), do: ctx.line

  defp file_line(line, ctx), do: (ctx[:first_line] || 1) + line - 1
end
