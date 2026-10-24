defmodule Mix.Tasks.App.Svelte do
  @shortdoc "Mirrors @svelte function components into .svelte files"

  @moduledoc """
  Writes a `.svelte` file next to every function component marked
  `@svelte true`, so the desktop and mobile apps can render the same UI
  without LiveView. The web app never uses these files: it keeps rendering
  the HEEx.

      @svelte true
      attr :title, :string, required: true
      slot :inner_block
      def status_card(assigns) do
        ~H\"\"\"
        <div class="card">{@title} {render_slot(@inner_block)}</div>
        \"\"\"
      end

  writes `StatusCard.svelte` in the same folder as the module. A component
  is generated when its whole body is one `~H` template using the part of
  HEEx that `HeexSvelte.Template` lists. Anything else in the template fails
  with the file and line, and the fix is either a simpler template or a
  `.svelte` file written by hand. A component with logic before its
  template, or more than one clause, can still be marked: its file is
  written by hand from the start and accepted, then checked like the rest.

  ## Usage

      mix app.svelte                  # write every file that is missing or generated
      mix app.svelte --check          # report files out of date with their component
      mix app.svelte --accept PATH    # after editing PATH by hand to match its component
      mix app.svelte --force          # regenerate files edited by hand too

  A file edited by hand is left alone. When its component changes, the
  file is out of date until it is edited to match and accepted, or
  regenerated with `--force`. `test/heex_svelte/sync_test.exs` runs the
  same check as `--check`, so `mix test` fails on a file left out of date.

  `phx-click`, `phx-submit` and `phx-change` become calls to the `emit`
  function the app provides with `setContext("app:emit", fn)`, called as
  `emit(event_name, payload, dom_event)`. The payload is the `phx-value-*`
  attributes for a click, and the form's `FormData` for a submit or change.
  `phx-click={JS.dispatch("name")}` instead dispatches the same DOM event
  LiveView would.
  """

  use Mix.Task

  @switches [check: :boolean, accept: :keep, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("compile")

    {components, problems} = HeexSvelte.components(Mix.Project.config()[:app])

    accepts = Keyword.get_values(opts, :accept)

    results =
      cond do
        opts[:check] ->
          HeexSvelte.check(components) ++ HeexSvelte.orphans(components)

        accepts != [] ->
          accept(components, accepts)

        true ->
          HeexSvelte.build(components, force: opts[:force] || false)
      end

    report(problems ++ results)
  end

  defp accept(components, paths) do
    components
    |> HeexSvelte.accept(paths)
    |> Enum.zip(paths)
    |> Enum.map(fn
      {:ok, path} ->
        {:accepted, path}

      {{:error, path}, _} ->
        {:error, %{file: path, line: 1, message: "no component marked @svelte writes this file"}}
    end)
  end

  defp report(results) do
    {problems, done} = Enum.split_with(results, &HeexSvelte.problem?/1)

    for result <- done do
      case result do
        {:unchanged, _path} -> :ok
        result -> Mix.shell().info(HeexSvelte.describe(result))
      end
    end

    for problem <- problems, do: Mix.shell().error(HeexSvelte.describe(problem))

    if problems != [] do
      Mix.raise("mix app.svelte found #{length(problems)} problem(s)")
    end
  end
end
