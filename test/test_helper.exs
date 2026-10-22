# The code generator tests fail when the project sits under a folder whose
# name starts with a dot, such as a Claude Code worktree in .claude/, since
# igniter's file lookup skips those folders. CI runs them, see
# MIX_TEST_INCLUDE in .github/workflows/protected-check.yml. Locally run them
# with `mix test --include code_generators`
ExUnit.start(exclude: [:code_generators])
Ecto.Adapters.SQL.Sandbox.mode(App.Repo, :manual)
