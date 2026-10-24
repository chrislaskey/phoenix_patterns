defmodule HeexSvelte.TemplateTest do
  use ExUnit.Case, async: true

  alias HeexSvelte.Template

  defp translate(source, opts \\ []) do
    ctx = %{
      attrs: Keyword.get(opts, :attrs, [:title, :items, :on, :id, :class, :rest, :count, :user]),
      slots: Keyword.get(opts, :slots, [:inner_block, :subtitle]),
      first_line: 10,
      resolve: fn
        :local_component, "icon" -> {:ok, "Icon", :icon_target}
        :remote_component, "Cards.card" -> {:ok, "Card", :card_target}
        _type, _name -> :error
      end
    }

    {markup, uses} = Template.translate(source, ctx)
    {String.trim(markup), uses}
  end

  defp markup(source, opts \\ []), do: source |> translate(opts) |> elem(0)

  defp error(source) do
    catch_throw(translate(source))
  end

  describe "markup" do
    test "keeps tags, text and static attributes" do
      assert markup(~s(<div class="a" id="b">Hi <b>there</b></div>)) ==
               ~s(<div class="a" id="b">Hi <b>there</b></div>)
    end

    test "escapes curly braces in text and attributes" do
      assert markup(~s(<p title="{x}" phx-no-curly-interpolation>a {b} c</p>)) ==
               ~s(<p title="&#123;x&#125;">a &#123;b&#125; c</p>)
    end

    test "keeps ampersands in attributes as written, like HEEx does" do
      assert markup(~s(<p class="[[data-theme=dark]_&]:block" title="a &amp; b"></p>)) ==
               ~s(<p class="[[data-theme=dark]_&]:block" title="a &amp; b"></p>)
    end

    test "closes self-closed tags that are not void" do
      assert markup(~s(<span class="a" /><br />)) == ~s(<span class="a"></span><br />)
    end

    test "turns HEEx comments into HTML comments" do
      assert markup("<%!-- note --%>") == "<!-- note -->"
    end
  end

  describe "expressions" do
    test "turns assigns and fields into props" do
      assert markup("<p>{@title} <%= @user.name %></p>") == "<p>{title} {user.name}</p>"
    end

    test "renames props that are JavaScript reserved words" do
      assert markup("<p class={@class}></p>") == "<p class={class_}></p>"
    end

    test "translates class lists, operators, if/2 and interpolation" do
      assert markup(~S|<p class={["a", @on && "b", if(@count > 1, do: "c", else: "d")]} id={"x-#{@id}"}></p>|) ==
               ~S|<p class={["a", on && "b", (count > 1 ? "c" : "d")]} id={`x-${id}`}></p>|
    end

    test "compares with [] as a list or slot check" do
      assert markup("<p :if={@items != []}></p><p :if={@subtitle == []}></p>") ==
               "{#if items.length > 0}<p></p>{/if}{#if subtitle == null}<p></p>{/if}"
    end

    test "spreads {@rest}" do
      assert markup("<button {@rest}>Go</button>") == "<button {...rest}>Go</button>"
    end
  end

  describe "blocks" do
    test "translates if, else and unless blocks" do
      assert markup("<%= if @on do %>yes<% else %>no<% end %><%= unless @on do %>off<% end %>") ==
               "{#if on}yes{:else}no{/if}{#if !(on)}off{/if}"
    end

    test "translates cond into an if chain" do
      source = """
      <%= cond do %>
        <% @count > 1 -> %>many
        <% @count == 1 -> %>one
        <% true -> %>none
      <% end %>
      """

      assert markup(source) =~
               ~r/^\{#if count > 1\}many\s*\{:else if count === 1\}one\s*\{:else\}none\s*\{\/if\}$/
    end

    test "translates for blocks and :for, :if and :key attributes" do
      assert markup("<%= for item <- @items do %>{item.label}<% end %>") ==
               "{#each items as item}{item.label}{/each}"

      assert markup(~s(<li :for={item <- @items} :if={item.on} :key={item.id}>{item.label}</li>)) ==
               "{#each items as item (item.id)}{#if item.on}<li>{item.label}</li>{/if}{/each}"
    end
  end

  describe "slots and components" do
    test "renders slots as snippets" do
      assert markup("{render_slot(@inner_block)}{render_slot(@subtitle, @title)}") ==
               "{@render children?.()}{@render subtitle?.(title)}"
    end

    test "records how each slot is rendered" do
      assert translate("{render_slot(@inner_block)}{render_slot(@subtitle, @title)}") |> elem(1) ==
               [{:render_slot, :inner_block, 0}, {:render_slot, :subtitle, 1}]
    end

    test "calls marked components and records them" do
      assert translate(~s(<.icon name="hero-x" class={@class} /><Cards.card>Body</Cards.card>)) ==
               {~s(<Icon name="hero-x" class={class_} /><Card>Body</Card>),
                [{:component, "Icon", :icon_target}, {:component, "Card", :card_target}]}
    end

    test "passes slot entries and :let as snippets" do
      assert markup(~s(<Cards.card :let={row}><:header>Top</:header>{row.name}</Cards.card>)) ==
               "<Card>{#snippet header()}Top{/snippet}{#snippet children(row)}{row.name}{/snippet}</Card>"
    end
  end

  describe "events" do
    test "turns phx-click and phx-value-* into an emit call" do
      assert translate(
               ~s(<button phx-click="save" phx-value-id={@id} phx-value-user-name="x" phx-target="#a">Go</button>)
             ) ==
               {~s|<button onclick={(event) => emit("save", {id: id, "user-name": "x"}, event)}>Go</button>|,
                [:emit]}
    end

    test "passes events on components as props" do
      assert markup(~s(<.icon name="hero-x" phx-click="close" />)) ==
               ~s|<Icon name="hero-x" onclick={(event) => emit("close", {}, event)} />|
    end

    test "turns phx-submit and phx-change on a form into emit calls with FormData" do
      assert markup(~s(<form phx-submit="save" phx-change="validate"></form>)) ==
               "<form onsubmit={(event) => { event.preventDefault(); emit(\"save\", new FormData(event.currentTarget), event) }} " <>
                 "oninput={(event) => { emit(\"validate\", new FormData(event.currentTarget), event) }}></form>"
    end
  end

  describe "JS.dispatch" do
    @dispatch "onclick={(event) => event.currentTarget.dispatchEvent(new CustomEvent("

    test "dispatches the event LiveView would, without emit" do
      assert translate(~s|<button phx-click={JS.dispatch("app:open")}>Go</button>|) ==
               {~s|<button #{@dispatch}"app:open", {bubbles: true, cancelable: true, | <>
                  ~s|detail: {dispatcher: event.currentTarget}}))}>Go</button>|, []}
    end

    test "passes detail: and bubbles:" do
      assert markup(
               ~s|<button phx-click={JS.dispatch("app:open", detail: %{id: @id}, bubbles: false)}></button>|
             ) ==
               ~s|<button #{@dispatch}"app:open", {bubbles: false, cancelable: true, | <>
                 ~s|detail: {id: id, dispatcher: event.currentTarget}}))}></button>|
    end

    test "passes the dispatch to a component as onclick" do
      assert markup(~s|<.icon name="hero-x" phx-click={JS.dispatch("app:close")} />|) =~
               ~s|<Icon name="hero-x" #{@dispatch}"app:close"|
    end

    test "rejects what it can't mirror" do
      for source <- [
            ~s|<button phx-click={JS.dispatch("app:open", to: "#modal")}></button>|,
            ~s|<button phx-click={JS.dispatch("click")}></button>|,
            ~s|<button phx-click={JS.dispatch(@id)}></button>|,
            ~s|<button phx-click={JS.dispatch("a", detail: @id)}></button>|,
            ~s|<button phx-click={JS.dispatch("a")} phx-value-id="1"></button>|,
            ~s|<button phx-click={JS.dispatch("a") \|> JS.push("b")}></button>|
          ] do
        assert {:heex_svelte, _line, "unsupported: " <> _} = error(source),
               "expected #{source} to be unsupported"
      end
    end
  end

  describe "unsupported" do
    test "reports the file line of the construct" do
      assert {:heex_svelte, 12, "unsupported: the call Enum.count(@items)"} =
               error("<div>\n\n  {Enum.count(@items)}\n</div>")
    end

    test "rejects what has no Svelte mirror" do
      for source <- [
            "<.link navigate={@id}>Go</.link>",
            "<.form for={@user}></.form>",
            "<div phx-hook=\"Chart\" id=\"c\"></div>",
            "<div phx-click={JS.toggle()}></div>",
            "<div phx-submit=\"save\"></div>",
            "<% x = 1 %>",
            "<%= case @id do %><% 1 -> %>one<% end %>",
            "<%= for {a, b} <- @items do %>{a}{b}<% end %>",
            "{@unknown}",
            "{@subtitle}",
            "<p :if={@items == [1]}></p>",
            "<script>alert(1)</script>"
          ] do
        assert {:heex_svelte, line, "unsupported: " <> _} = error(source),
               "expected #{source} to be unsupported"

        assert is_integer(line)
      end
    end
  end
end
