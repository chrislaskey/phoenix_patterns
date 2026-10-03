# Configuration for `mix check` (ex_check), the one command to run before a
# commit. It runs every tool in parallel and reports them together. CI runs
# the same command, see .github/workflows/protected-check.yml.
#
#     $ mix check          # run everything
#     $ mix check --retry  # rerun only the tools that failed last time
#     $ mix check --fix    # also apply fixes: `mix format`, `mix deps.unlock --unused`
#
# Besides the tools listed here, ex_check runs its defaults for whatever the
# project has: compiler, unused_deps, formatter, hex_audit, credo, ex_unit,
# gettext. See `mix help check`.

# CI sets APP_CHECKS_BASE to the pull request's base branch, so the review
# tier check measures a pull request opened against another branch against
# that branch. Locally it is unset and `.app_checks.exs` decides.
app_checks_base =
  case System.get_env("APP_CHECKS_BASE") do
    base when base in [nil, ""] -> ""
    base -> " --base " <> base
  end

[
  # Always run every tool. Without this, a run after a failure silently reruns
  # only the tools that failed last time, so a problem introduced while fixing
  # another is missed. Pass --retry to opt in for one run.
  retry: false,
  # Do not list the tools that are skipped because their package is not
  # installed, such as dialyzer and sobelow. Pass --skipped to see them.
  skipped: false,
  tools: [
    # Custom checks in priv/checks, see `mix help app.checks`
    {:app_checks, "mix app.checks" <> app_checks_base}
  ]
]
