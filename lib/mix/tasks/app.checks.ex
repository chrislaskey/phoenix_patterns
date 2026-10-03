defmodule Mix.Tasks.App.Checks do
  @shortdoc "Runs the custom checks in priv/checks"

  @moduledoc """
  Builds and runs the custom checks in `priv/checks`, a small Rust program.
  See `priv/checks/README.md` for how the checks work and how to add one.

      $ mix app.checks                 # scans the configured paths, lib/ by default
      $ mix app.checks lib test        # or any files and directories
      $ mix app.checks --base feature  # compare the branch with another base

  There are two kinds of check. Source checks read the files under the given
  paths. Branch checks look at what the current branch changed compared with
  a base branch, `origin/main` unless configured otherwise, and ignore the
  paths. Git is only read, never fetched. For a branch that builds on another
  unmerged branch, pass `--base` with that branch.

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
        disabled_checks: [],
        base: "origin/main"
      ]

  Every file in `priv/checks/src/checks` is a check. `disabled_checks` names
  the ones to skip by file name, so `[:raw_html_tags]` turns off
  `raw_html_tags.rs`. Naming a check that does not exist is an error.

  Any other key is the name of a check and holds that check's settings as a
  keyword list. Each setting becomes a `--set check.key=value` flag. A list
  gives the flag once per element and a nested keyword list adds a segment to
  the key, so this:

      review_tier: [
        default: :high,
        protected: [agents: ["AGENTS.md"]],
        high: ["config/**", "mix.exs"]
      ]

  becomes `--set review_tier.default=high`,
  `--set review_tier.protected.agents=AGENTS.md`,
  `--set review_tier.high=config/**` and `--set review_tier.high=mix.exs`.
  A setting the check does not accept is an error.

  Paths given on the command line replace `paths` for that run.
  """

  use Mix.Task

  @manifest "priv/checks/Cargo.toml"
  @binary "priv/checks/target/release/checks"
  @config_file ".app_checks.exs"
  @defaults [
    paths: ["lib"],
    paths_to_ignore: ["_build", "deps", "node_modules"],
    disabled_checks: [],
    base: "origin/main"
  ]
  @list_keys [:paths, :paths_to_ignore, :disabled_checks]

  @impl Mix.Task
  def run(args) do
    {options, paths} = OptionParser.parse!(args, strict: [base: :string])
    build()

    @config_file
    |> load_config()
    |> Keyword.merge(options)
    |> run_checks(paths)
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
  The command line arguments for the program: `--base`, one `--ignore` per
  ignored directory, one `--disable` per disabled check, one `--set` per
  check setting, then the paths to scan.
  """
  def arguments(config, paths) do
    base = ["--base", config[:base]]
    ignore = Enum.flat_map(config[:paths_to_ignore], &["--ignore", &1])
    disable = Enum.flat_map(config[:disabled_checks], &["--disable", to_string(&1)])
    set = Enum.flat_map(settings(config), &["--set", &1])
    scan = if paths == [], do: config[:paths], else: paths

    base ++ ignore ++ disable ++ set ++ scan
  end

  @doc """
  Every check setting in `config` as a `check.key=value` string, in order.
  """
  def settings(config) do
    config
    |> Keyword.drop(Keyword.keys(@defaults))
    |> Enum.flat_map(fn {check, settings} -> flatten(to_string(check), settings) end)
  end

  defp flatten(prefix, value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.flat_map(value, fn {key, inner} -> flatten("#{prefix}.#{key}", inner) end)
    else
      Enum.flat_map(value, &flatten(prefix, &1))
    end
  end

  defp flatten(prefix, value), do: ["#{prefix}=#{value}"]

  defp validate!(config, path) do
    unless Keyword.keyword?(config) do
      Mix.raise("#{path} must be a keyword list, see `mix help app.checks`")
    end

    for key <- @list_keys, value = config[key], not is_list(value) do
      Mix.raise("#{path}: #{key} must be a list, got #{inspect(value)}")
    end

    base = Keyword.get(config, :base, "")

    unless is_binary(base) do
      Mix.raise("#{path}: base must be a string naming a branch or commit, got #{inspect(base)}")
    end

    for {key, value} <- Keyword.drop(config, Keyword.keys(@defaults)),
        not Keyword.keyword?(value) do
      Mix.raise(
        "#{path}: #{key} must be a keyword list of settings for the check called #{key}, " <>
          "got #{inspect(value)}; the other keys are #{inspect(Keyword.keys(@defaults))}"
      )
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
