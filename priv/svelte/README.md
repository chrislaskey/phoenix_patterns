# Svelte mirrors of function components

The web app renders HEEx with LiveView, and nothing changes there. For the
desktop and mobile apps, `mix app.svelte` writes a `.svelte` copy of each
function component marked `@svelte true`, in the same folder as the
component, so the two copies sit together and are changed together.

```elixir
@svelte true
attr :title, :string, required: true
slot :inner_block

def status_card(assigns) do
  ~H"""
  <div class="card">{@title} {render_slot(@inner_block)}</div>
  """
end
```

writes `StatusCard.svelte` next to the module. Commit the `.svelte` files:
the other apps import them as source and build without Elixir.

## Run

```sh
mix app.svelte                  # write every file that is missing or generated
mix app.svelte --check          # report files out of date with their component
mix app.svelte --accept PATH    # after editing PATH by hand to match its component
mix app.svelte --force          # regenerate files edited by hand too
```

It is a manual step, not part of `mix compile`. `test/heex_svelte/sync_test.exs`
fails `mix test`, and so `mix check`, when a file is out of date with its
component, missing, or left over from a component no longer marked.

## Generated or edited by hand

Each file starts with a header holding two hashes: one of the component's
template and attr and slot declarations, and one of what the generator
wrote. From those the tool tells a file it generated from one edited by
hand, and either from one that is out of date:

| The file is | `mix app.svelte` | `mix app.svelte --check` |
| --- | --- | --- |
| Missing, or generated and untouched | writes it | reports it when out of date |
| Edited by hand, component unchanged | leaves it | passes |
| Edited by hand, component changed | leaves it, reports it | reports it |
| There without a header | reports it | reports it |
| Missing, for a component that can't be generated | reports it | reports it |

Edit a file by hand when the generator cannot mirror a template, or gets it
wrong. When its component changes, update the file to match and run
`mix app.svelte --accept PATH`. That records the component as matched and
keeps the file as edited, so the generator still leaves it alone. To adopt
a `.svelte` file written from scratch, `--accept` it too.

A component the generator can't follow at all, because it has logic before
its template or more than one clause, can still be marked. Its file is
written by hand from the start, like `Button.svelte` for `button/1`, and
is checked against the whole component rather than its template: any
change to the function makes it stale until it's updated and accepted.
`mix app.svelte` reports such a component until its file exists.

## What a marked component may use

To be generated, the component is one `def` or `defp` clause whose whole
body is a `~H` template. Logic that runs before the template, such as
`assign_new`, belongs in an attr default or the caller, or the file is
written by hand. A component with no `attr` or `slot` declarations has no
props.

| HEEx | Svelte |
| --- | --- |
| `{@title}`, `{@user.name}`, `@map[:key]` | `{title}`, `{user.name}`, `map["key"]` |
| Literals, lists, `"a #{b}"`, `if(c, do: a, else: b)` | the JavaScript equivalent |
| `==`, `!=`, `<`, `>`, `&&`, `\|\|`, `!`, `and`, `or`, `not`, `<>` | `===`, `!==`, `<`, `>`, `&&`, `\|\|`, `!`, `+` |
| `@items != []`, `@subtitle != []` for a slot | `items.length > 0`, `subtitle != null` |
| `class={["a", @on && "b"]}` | the same list, which Svelte joins the same way |
| `<%= if %>`, `<%= unless %>`, `<%= cond %>`, `<%= for x <- @xs %>` | `{#if}`, `{:else if}`, `{#each}` |
| `:if`, `:for`, `:key` | `{#if}` and `{#each xs as x (key)}` around the tag |
| `{@rest}` | `{...rest}` |
| `render_slot(@inner_block)`, `render_slot(@header, arg)` | `{@render children?.()}`, `{@render header?.(arg)}` |
| `<.icon>`, `<Layouts.app>` for components marked `@svelte` | `<Icon>`, imported from its file |
| `<:header>` and `:let={row}` | `{#snippet header()}`, `{#snippet children(row)}` |
| `phx-click="save" phx-value-id={@id}` | `onclick={(event) => emit("save", {id: id}, event)}` |
| `phx-submit`, `phx-change` on a `<form>` | `emit(name, new FormData(form), event)` |
| `phx-click={JS.dispatch("app:open", detail: %{id: @id})}` | the same DOM event LiveView dispatches, see below |

Attrs become props with the same names, so the apps pass the same data the
LiveView assigns. A name that is a JavaScript reserved word gets an
underscore inside the file only: `attr :class` is still the `class` prop.
Types and defaults come from the `attr` declarations, as JSDoc.

`phx-target`, `phx-disable-with`, `phx-debounce`, `phx-throttle`,
`phx-page-loading` and `phx-no-curly-interpolation` are dropped. Anything
else fails with the file and line: other `phx-*` attributes, `JS` commands
other than a single `JS.dispatch`,
function calls, `case`, `<% %>` without `=`, `<.link>`, `<.form>`, slot
entries with attributes, and colocated scripts.

Two differences from Elixir to keep in mind:

* JavaScript treats `0` and `""` as false, where Elixir treats only `nil`
  and `false` that way. `:if={@count}` hides a count of `0` in Svelte
* `==` compiles to `===`, so it compares lists and maps by reference.
  Comparing with a list or map literal other than `[]` fails the build

## Styling

The files keep the template's Tailwind, daisyUI and `hero-*` classes. The
daisyUI plugin, the light and dark themes and the `dark` variant are in
`assets/css/theme.css`, which `assets/css/app.css` imports and the other
apps import too, so a component looks the same everywhere. Put anything
only LiveView needs in `app.css`.

Slots are typed `Snippet<[]>`, or `Snippet<[any]>` when the template
renders them with an argument, from how the template calls `render_slot`.

## Events

`emit` comes from Svelte context, so each app decides what an event does:

```js
import { setContext } from "svelte"

setContext("app:emit", (name, payload, event) => {
  // online: forward to the server, offline: handle locally
})
```

The payload is an object of the `phx-value-*` attributes for a click and the
form's `FormData` for a submit or change. A component without a handler
logs a warning instead of failing.

`JS.dispatch` is different: it never reaches the server in LiveView either,
so it doesn't go through `emit`. The click dispatches the same DOM event
LiveView's client would, on the clicked element: cancelable, bubbling unless
`bubbles: false`, with `detail:` plus `dispatcher`, the clicked element. A
listener written for the web, like the `phx:set-theme` one in
`assets/js/theme_script.js`, works unchanged in the other apps. `to:` and chained
commands aren't supported.

## How it works

* `HeexSvelte.Source` finds the marked defs in a module's source file and
  takes their attrs and slots from `__components__/0`
* `HeexSvelte.Template` parses the template with LiveView's own HEEx parser,
  `Phoenix.LiveView.TagEngine.Parser`, and writes the markup
* `HeexSvelte.Expr` translates the Elixir in `{...}` and attributes
* `HeexSvelte.SvelteFile` writes the script, the props and the header

The parser is internal to LiveView, so a LiveView upgrade can change it.
`test/heex_svelte` covers every construct above, so a change shows up as a
failing test rather than a wrong file.

```sh
mix test test/heex_svelte
```
