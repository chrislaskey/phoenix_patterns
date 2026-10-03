defmodule Mix.Tasks.App.ChecksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.App.Checks

  @moduletag :tmp_dir

  @defaults Checks.load_config("/no/such/file")

  # The branch check reads git, so the source check tests turn it off and
  # stay independent of the state of this repository.
  @source_only Keyword.put(@defaults, :disabled_checks, [:review_tier])

  describe "load_config/1" do
    test "returns the defaults when there is no file" do
      assert @defaults == [
               paths: ["lib"],
               paths_to_ignore: ["_build", "deps", "node_modules"],
               disabled_checks: [],
               base: "origin/main"
             ]
    end

    test "fills in defaults for keys the file leaves out", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[disabled_checks: [:raw_html_tags]]")

      assert Enum.sort(Checks.load_config(path)) ==
               Enum.sort(
                 paths: ["lib"],
                 paths_to_ignore: ["_build", "deps", "node_modules"],
                 disabled_checks: [:raw_html_tags],
                 base: "origin/main"
               )
    end

    test "keeps check settings as given", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[review_tier: [default: :standard]]")

      assert Checks.load_config(path)[:review_tier] == [default: :standard]
    end

    test "rejects values that are not lists", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[paths: \"lib\"]")

      assert_raise Mix.Error, ~r/paths must be a list/, fn -> Checks.load_config(path) end
    end

    test "rejects a base that is not a string", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[base: :main]")

      assert_raise Mix.Error, ~r/base must be a string/, fn -> Checks.load_config(path) end
    end

    test "rejects an unknown key that is not a keyword list of settings", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[ignore: [\"deps\"]]")

      assert_raise Mix.Error, ~r/ignore must be a keyword list.*check called ignore/, fn ->
        Checks.load_config(path)
      end
    end
  end

  describe "settings/1" do
    test "flattens each check's settings into dotted keys, one per list element" do
      config =
        Keyword.put(@defaults, :review_tier,
          default: :high,
          protected: [agents: ["AGENTS.md"], lint_config: [".credo.exs", ".check.exs"]],
          high: ["config/**", "mix.exs"]
        )

      assert Checks.settings(config) == [
               "review_tier.default=high",
               "review_tier.protected.agents=AGENTS.md",
               "review_tier.protected.lint_config=.credo.exs",
               "review_tier.protected.lint_config=.check.exs",
               "review_tier.high=config/**",
               "review_tier.high=mix.exs"
             ]
    end

    test "is empty when no check has settings" do
      assert Checks.settings(@defaults) == []
    end
  end

  describe "arguments/2" do
    test "turns the config into flags followed by the configured paths" do
      config = [
        paths: ["lib", "test"],
        paths_to_ignore: ["deps"],
        disabled_checks: [:a, :b],
        base: "origin/develop",
        review_tier: [low: ["docs/**"]]
      ]

      assert Checks.arguments(config, []) == [
               "--base",
               "origin/develop",
               "--ignore",
               "deps",
               "--disable",
               "a",
               "--disable",
               "b",
               "--set",
               "review_tier.low=docs/**",
               "lib",
               "test"
             ]
    end

    test "paths given on the command line replace the configured ones" do
      assert Checks.arguments(@defaults, ["lib/x.ex"]) ==
               ["--base", "origin/main"] ++
                 ["--ignore", "_build", "--ignore", "deps", "--ignore", "node_modules"] ++
                 ["lib/x.ex"]
    end
  end

  # The task scans whatever paths it is given, so each test writes one template
  # into its own directory and points the task at that.
  #
  # Output is captured from this process rather than by swapping the global
  # Mix shell, which would also redirect output from concurrent tests.
  describe "run_checks/2 with source checks" do
    test "passes when no finding is confirmed", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div><.p>Hello</.p><pre>x</pre></div>\n")

      output = capture_io(fn -> assert :ok = Checks.run_checks(@source_only, [path]) end)

      assert output =~ "0 confirmed finding(s)"
    end

    test "fails when a finding is confirmed", %{tmp_dir: dir} do
      path = write(dir, "raw.html.heex", "<div>\n  <p>Hello</p>\n</div>\n")

      output =
        capture_io(fn ->
          assert_raise Mix.Error, ~r/found problems/, fn ->
            Checks.run_checks(@source_only, [path])
          end
        end)

      assert output =~ "#{path}:2: <p> is a raw tag"
      assert output =~ "1 confirmed finding(s)"
    end

    test "a disabled check does not run", %{tmp_dir: dir} do
      path = write(dir, "raw.html.heex", "<p>Hello</p>\n")
      config = Keyword.put(@defaults, :disabled_checks, [:raw_html_tags, :review_tier])

      output = capture_io(fn -> assert :ok = Checks.run_checks(config, [path]) end)

      assert output =~ "0 check(s)"
      assert output =~ "2 disabled"
    end

    test "disabling a check that does not exist is an error", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div />\n")
      config = Keyword.put(@source_only, :disabled_checks, [:nope])

      assert_raise Mix.Error, ~r/could not run/, fn -> Checks.run_checks(config, [path]) end
    end

    test "skips ignored directories inside a scanned path", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "deps"))
      write(dir, "deps/raw.html.heex", "<p>Hello</p>\n")
      config = Keyword.put(@source_only, :paths_to_ignore, ["deps"])

      output = capture_io(fn -> assert :ok = Checks.run_checks(config, [dir]) end)

      assert output =~ "over 0 file(s)"
    end
  end

  # These run the branch check against this repository, so they only assert
  # on what holds for any branch: the tier line is printed and bad settings
  # are refused before anything runs.
  describe "run_checks/2 with the branch check" do
    test "prints the review tier", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div />\n")
      config = Keyword.put(@defaults, :disabled_checks, [:raw_html_tags])

      output = capture_io(fn -> Checks.run_checks(config, [path]) end)

      assert output =~
               ~r/^review tier: \w+, \d+ file\(s\) changed against origin\/main \[review_tier, info\]$/m
    end

    test "a setting the check does not accept is an error", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div />\n")
      config = Keyword.put(@defaults, :review_tier, nope: ["x"])

      output =
        capture_io(fn ->
          assert_raise Mix.Error, ~r/could not run/, fn -> Checks.run_checks(config, [path]) end
        end)

      assert output =~ "review_tier does not accept nope"
    end
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end
end
