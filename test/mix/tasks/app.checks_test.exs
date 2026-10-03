defmodule Mix.Tasks.App.ChecksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.App.Checks

  @moduletag :tmp_dir

  @defaults Checks.load_config("/no/such/file")

  describe "load_config/1" do
    test "returns the defaults when there is no file" do
      assert @defaults == [
               paths: ["lib"],
               paths_to_ignore: ["_build", "deps", "node_modules"],
               disabled_checks: []
             ]
    end

    test "fills in defaults for keys the file leaves out", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[disabled_checks: [:raw_html_tags]]")

      assert Checks.load_config(path) == [
               paths: ["lib"],
               paths_to_ignore: ["_build", "deps", "node_modules"],
               disabled_checks: [:raw_html_tags]
             ]
    end

    test "rejects unknown keys, so a typo cannot be ignored", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[ignore: [\"deps\"]]")

      assert_raise Mix.Error, ~r/unknown key.*:ignore.*paths_to_ignore/, fn ->
        Checks.load_config(path)
      end
    end

    test "rejects values that are not lists", %{tmp_dir: dir} do
      path = write(dir, ".app_checks.exs", "[paths: \"lib\"]")

      assert_raise Mix.Error, ~r/paths must be a list/, fn -> Checks.load_config(path) end
    end
  end

  describe "arguments/2" do
    test "turns the config into flags followed by the configured paths" do
      config = [paths: ["lib", "test"], paths_to_ignore: ["deps"], disabled_checks: [:a, :b]]

      assert Checks.arguments(config, []) ==
               ["--ignore", "deps", "--disable", "a", "--disable", "b", "lib", "test"]
    end

    test "paths given on the command line replace the configured ones" do
      assert Checks.arguments(@defaults, ["lib/x.ex"]) ==
               ["--ignore", "_build", "--ignore", "deps", "--ignore", "node_modules", "lib/x.ex"]
    end
  end

  # The task scans whatever paths it is given, so each test writes one template
  # into its own directory and points the task at that.
  #
  # Output is captured from this process rather than by swapping the global
  # Mix shell, which would also redirect output from concurrent tests.
  describe "run_checks/2" do
    test "passes when no finding is confirmed", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div><.p>Hello</.p><pre>x</pre></div>\n")

      output = capture_io(fn -> assert :ok = Checks.run_checks(@defaults, [path]) end)

      assert output =~ "0 confirmed finding(s)"
    end

    test "fails when a finding is confirmed", %{tmp_dir: dir} do
      path = write(dir, "raw.html.heex", "<div>\n  <p>Hello</p>\n</div>\n")

      output =
        capture_io(fn ->
          assert_raise Mix.Error, ~r/found problems/, fn ->
            Checks.run_checks(@defaults, [path])
          end
        end)

      assert output =~ "#{path}:2: <p> is a raw tag"
      assert output =~ "1 confirmed finding(s)"
    end

    test "a disabled check does not run", %{tmp_dir: dir} do
      path = write(dir, "raw.html.heex", "<p>Hello</p>\n")
      config = Keyword.put(@defaults, :disabled_checks, [:raw_html_tags])

      output = capture_io(fn -> assert :ok = Checks.run_checks(config, [path]) end)

      assert output =~ "0 check(s)"
      assert output =~ "1 disabled"
    end

    test "disabling a check that does not exist is an error", %{tmp_dir: dir} do
      path = write(dir, "clean.html.heex", "<div />\n")
      config = Keyword.put(@defaults, :disabled_checks, [:nope])

      assert_raise Mix.Error, ~r/could not run/, fn -> Checks.run_checks(config, [path]) end
    end

    test "skips ignored directories inside a scanned path", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "deps"))
      write(dir, "deps/raw.html.heex", "<p>Hello</p>\n")
      config = Keyword.put(@defaults, :paths_to_ignore, ["deps"])

      output = capture_io(fn -> assert :ok = Checks.run_checks(config, [dir]) end)

      assert output =~ "over 0 file(s)"
    end
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end
end
