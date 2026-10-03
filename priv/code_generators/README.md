# Code generators

Mix tasks that write code the same way every time, built with the
[igniter](https://hexdocs.pm/igniter) library. Igniter parses a file into its
syntax tree, changes the tree and writes the file back formatted, so a
generator can add a route to the router or a function to a module without
guessing at text.

| Task | Use it to |
| --- | --- |
| `mix app.gen.live NAME PATH` | Add a page: the LiveView, its route and its test |
| `mix app.gen.component NAME` | Add a function component to `CoreComponents` |

Each task's moduledoc says when to use it and what it writes. Read it with
`mix help app.gen.live`, or in the file.

## Run

```sh
mix app.gen.live Dashboard /dashboard   # prints the changes and asks before writing
mix app.gen.live Dashboard /dashboard --dry-run   # prints the changes only
mix app.gen.live Dashboard /dashboard --yes       # writes without asking
```

Every generator refuses to overwrite. When the module or function it would
add already exists, it reports the problem and changes nothing. A generator
also never leaves a file half done: all its changes are written together or
not at all.

The generators are compiled in `dev` and `test` only, which is where the
`igniter` dependency lives. `mix.exs` lists this folder in `elixirc_paths`
for those two environments.

## Config

`.igniter.exs` in the project root. Igniter moves a module to the folder
that matches its name, which would take a LiveView out of the `live/`
folder Phoenix keeps them in. The `dont_move_files` key lists the paths it
must leave alone. See `mix help igniter.setup`.

## Add a generator

1. Create `priv/code_generators/app.gen.NAME.ex` defining
   `Mix.Tasks.App.Gen.Name` with `use Igniter.Mix.Task`. The task name
   decides the module name and the other way round, so keep them matched.
2. Write the moduledoc first: when to use the task, an example command and
   what it writes. The moduledoc is what an engineer or an LLM reads to
   decide whether to run it.
3. Return the arguments from `info/2` and do the work in `igniter/1`.
   Create files with `Igniter.create_new_file/3` and change existing ones
   with `Igniter.Project.Module.find_and_update_module/3`. Report a problem
   with `Igniter.add_issue/2` rather than raising, so nothing is written.
4. Add a test in `test/code_generators`. Build the project in memory with
   `Igniter.Test.test_project/1`, run the task with `Igniter.compose_task/3`
   and check the result with `assert_creates/3`, `assert_has_patch/3` and
   `assert_has_issue/3`. No files are written during a test.
5. Add the task to the table above and to `AGENTS.md`.

Nothing in this folder is named after the application. The generators read
the web module from `mix.exs`, so the folder can be copied to another
Phoenix project as it is.

## Test

```sh
mix test test/code_generators
```
