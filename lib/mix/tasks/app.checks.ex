defmodule Mix.Tasks.App.Checks do
  @shortdoc "Runs the custom source code checks in priv/checks"

  @moduledoc """
  Builds and runs the custom source code checks in `priv/checks`, a small Rust
  program. See `priv/checks/README.md` for how the checks work and how to add
  one.

      $ mix app.checks            # scans the configured paths, lib/ by default
      $ mix app.checks lib test   # or any files and directories

  The program is built before every run. When nothing in `priv/checks`
  changed, cargo sees that and the build finishes at once, so a run costs
  about as much as the scan itself. Rust is pinned in `.tool-versions`.

  The task fails when any finding is confirmed, which is what `mix check`
  (ex_check) looks for. It is listed as a tool in `.check.exs`.

  ## Configuration

  `.app_checks.exs` in the project root. Every key is optional and these are
  the defaults:

      [
        paths: ["lib"],
        paths_to_ignore: ["_build", "deps", "node_modules"],
        disabled_checks: []
      ]

  Every file in `priv/checks/src/checks` is a check. `disabled_checks` names
  the ones to skip by file name, so `[:raw_html_tags]` turns off
  `raw_html_tags.rs`. Naming a check that does not exist is an error.

  Paths given on the command line replace `paths` for that run.
  """

  use Mix.Task

  @manifest "priv/checks/Cargo.toml"
  @binary "priv/checks/target/release/checks"
  @config_file ".app_checks.exs"
  @defaults [
    paths: ["lib"],
    paths_to_ignore: ["_build", "deps", "node_modules"],
    disabled_checks: []
  ]

  @impl Mix.Task
  def run(args) do
    build()
    run_checks(load_config(@config_file), args)
  end

  @doc """
  Runs the built program with `config` over `paths`, or over the configured
  paths when `paths` is empty. Raises when a finding is confirmed.
  """
  def run_checks(config, paths) do
    case System.cmd(Path.expand(@binary), arguments(config, paths),
           into: IO.stream(),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, 1} ->
        Mix.raise("mix app.checks found problems, see the findings above")

      {_, status} ->
        Mix.raise("mix app.checks could not run (exit status #{status}), see the message above")
    end
  end

  @doc """
  Reads the config file at `path`, filling in defaults for missing keys. A
  missing file means all defaults.
  """
  def load_config(path) do
    if File.exists?(path) do
      {config, _bindings} = Code.eval_file(path)
      validate!(config, path)
      Keyword.merge(@defaults, config)
    else
      @defaults
    end
  end

  @doc """
  The command line arguments for the program: one `--ignore` per ignored
  directory, one `--disable` per disabled check, then the paths to scan.
  """
  def arguments(config, paths) do
    ignore = Enum.flat_map(config[:paths_to_ignore], &["--ignore", &1])
    disable = Enum.flat_map(config[:disabled_checks], &["--disable", to_string(&1)])
    scan = if paths == [], do: config[:paths], else: paths

    ignore ++ disable ++ scan
  end

  defp validate!(config, path) do
    unless Keyword.keyword?(config) do
      Mix.raise("#{path} must be a keyword list, see `mix help app.checks`")
    end

    case Keyword.keys(config) -- Keyword.keys(@defaults) do
      [] ->
        :ok

      unknown ->
        Mix.raise(
          "#{path} has unknown key(s) #{inspect(unknown)}, the keys are #{inspect(Keyword.keys(@defaults))}"
        )
    end

    for {key, value} <- config, not is_list(value) do
      Mix.raise("#{path}: #{key} must be a list, got #{inspect(value)}")
    end
  end

  defp build do
    unless System.find_executable("cargo") do
      Mix.raise("""
      cargo was not found, so the checks in priv/checks could not be built.
      Install Rust with `asdf install` (the version is in .tool-versions)
      or from https://rustup.rs
      """)
    end

    unless File.exists?(@binary) do
      Mix.shell().info("Compiling #{Path.dirname(@manifest)}, this only happens on the first run")
    end

    cargo = ["build", "--release", "--quiet", "--manifest-path", @manifest]

    case System.cmd("cargo", cargo, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("could not build #{Path.dirname(@manifest)}:\n\n" <> output)
    end
  end
end
