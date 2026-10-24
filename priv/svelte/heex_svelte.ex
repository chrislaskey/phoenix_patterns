defmodule HeexSvelte do
  @moduledoc """
  Mirrors function components marked `@svelte true` into `.svelte` files
  next to them, for apps that render the same UI without LiveView. See
  `priv/svelte/README.md` and `mix help app.svelte`.
  """

  alias HeexSvelte.{Source, SvelteFile}

  @doc """
  The marked components of `app`'s modules, as `{components, problems}`.
  The app must be compiled.
  """
  def components(app) do
    _ = Application.load(app)

    {components, problems} =
      app
      |> Application.spec(:modules)
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__components__, 0)))
      |> Enum.map(&Source.components/1)
      |> Enum.reduce({[], []}, fn {components, errors}, {all, problems} ->
        {all ++ components, problems ++ Enum.map(errors, &{:error, &1})}
      end)

    {components, problems ++ collisions(components)}
  end

  defp collisions(components) do
    components
    |> Enum.group_by(&SvelteFile.path/1)
    |> Enum.filter(fn {_path, components} -> length(components) > 1 end)
    |> Enum.map(fn {path, [component | _] = components} ->
      names = Enum.map_join(components, ", ", &name/1)
      {:error, %{file: component.file, line: component.line, message: "#{names} would all write #{path}"}}
    end)
  end

  @doc """
  Writes the `.svelte` file of every component in `components`, leaving
  files edited by hand alone unless `force: true`.

  Returns a list of `{:written | :unchanged | :edited, path}` results and
  `{:stale_edit | :no_header, path}`, `{:hand_write, details}` or
  `{:error, error}` problems. A component that can't be generated, see
  `HeexSvelte.Source`, is only ever checked, never written.
  """
  def build(components, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    Enum.map(components, fn component ->
      path = SvelteFile.path(component)
      hand_written? = component.hand_written != nil

      case SvelteFile.read(path) do
        {:error, :no_header} ->
          {:no_header, path}

        {:ok, %{edited?: true, source: source}} when hand_written? or not force? ->
          if source == SvelteFile.source_hash(component), do: {:edited, path}, else: {:stale_edit, path}

        _missing_or_generated when hand_written? ->
          hand_write(component, path)

        _missing_or_generated ->
          write(component, path, components)
      end
    end)
  end

  defp write(component, path, components) do
    case SvelteFile.render(component, &resolve(components, &1, &2, &3)) do
      {:ok, contents} ->
        if File.read(path) == {:ok, contents} do
          {:unchanged, path}
        else
          File.write!(path, contents)
          {:written, path}
        end

      {:error, line, message} ->
        {:error, %{file: component.file, line: line, message: "#{name(component)}: #{message}"}}
    end
  end

  defp hand_write(component, path) do
    {:hand_write, %{path: path, component: name(component), reason: component.hand_written}}
  end

  @doc """
  Checks the `.svelte` file of every component without writing anything.

  Returns `{:missing | :stale | :no_header, path}` for each file that does
  not match its component.
  """
  def check(components) do
    Enum.flat_map(components, fn component ->
      path = SvelteFile.path(component)

      case SvelteFile.read(path) do
        {:error, :enoent} when component.hand_written != nil ->
          [hand_write(component, path)]

        {:error, :enoent} ->
          [{:missing, path}]

        {:error, :no_header} ->
          [{:no_header, path}]

        {:ok, %{source: source}} ->
          if source == SvelteFile.source_hash(component), do: [], else: [{:stale, path}]
      end
    end)
  end

  @doc """
  Returns `{:orphan, path}` for each generated file matching `pattern`
  whose component is no longer marked.
  """
  def orphans(components, pattern \\ "lib/**/*.svelte") do
    paths = MapSet.new(components, &SvelteFile.path/1)

    for path <- Path.wildcard(pattern),
        not MapSet.member?(paths, path),
        SvelteFile.generated?(File.read!(path)),
        do: {:orphan, path}
  end

  @doc """
  Restamps the files at `paths` with their components' current source
  hash, after editing them by hand. Returns `:ok` or `{:error, path}` for
  a path no marked component writes.
  """
  def accept(components, paths) do
    by_path = Map.new(components, &{Path.expand(SvelteFile.path(&1)), &1})

    Enum.map(paths, fn path ->
      case Map.fetch(by_path, Path.expand(path)) do
        {:ok, component} -> SvelteFile.accept(path, component)
        _ -> {:error, path}
      end
    end)
  end

  @doc "Describes a result or problem from `build/2`, `check/1` or `components/1` for a person."
  def describe({:written, path}), do: "wrote #{path}"
  def describe({:unchanged, path}), do: "unchanged #{path}"
  def describe({:accepted, path}), do: "accepted #{path}"
  def describe({:edited, path}), do: "kept #{path}, edited by hand and up to date"
  def describe({:missing, path}), do: "#{path} is missing, run `mix app.svelte`"

  def describe({:stale, path}) do
    "#{path} is out of date with its component. Run `mix app.svelte`, or for a file " <>
      "edited by hand, update it and run `mix app.svelte --accept #{path}`"
  end

  def describe({:stale_edit, path}) do
    "#{path} was edited by hand and its component has changed since. Update it and run " <>
      "`mix app.svelte --accept #{path}`, or regenerate it with `mix app.svelte --force`"
  end

  def describe({:no_header, path}) do
    "#{path} has no heex-svelte header. Adopt it as hand-written with " <>
      "`mix app.svelte --accept #{path}`, or delete it to generate it"
  end

  def describe({:hand_write, %{path: path, component: component, reason: reason}}) do
    "#{component} can't be generated, since #{reason}. Write #{path} by hand to match it " <>
      "and run `mix app.svelte --accept #{path}`, or simplify the component"
  end

  def describe({:orphan, path}),
    do: "#{path} was generated for a component no longer marked @svelte, delete it"

  def describe({:error, %{file: file, line: line, message: message}}), do: "#{file}:#{line}: #{message}"

  @doc "True for the results of `build/2` that need someone to act."
  def problem?({kind, _}), do: kind not in [:written, :unchanged, :edited, :accepted]

  defp resolve(components, from, :local_component, name) do
    function = String.to_existing_atom(name)
    same_module = Enum.filter(components, &(&1.module == from.module and &1.function == function))
    by_name = Enum.filter(components, &(&1.function == function))

    case {same_module, by_name} do
      {[target], _} -> {:ok, SvelteFile.svelte_name(target.function), target}
      {[], [target]} -> {:ok, SvelteFile.svelte_name(target.function), target}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp resolve(components, _from, :remote_component, name) do
    {alias_name, function} = name |> String.split(".") |> Enum.split(-1)
    alias_name = Enum.join(alias_name, ".")

    components
    |> Enum.filter(fn component ->
      module = inspect(component.module)

      to_string(component.function) == hd(function) and
        (module == alias_name or String.ends_with?(module, "." <> alias_name))
    end)
    |> case do
      [target] -> {:ok, SvelteFile.svelte_name(target.function), target}
      _ -> :error
    end
  end

  defp name(component), do: "#{inspect(component.module)}.#{component.function}/1"
end
