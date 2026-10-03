# Configuration for `mix check` (ex_check), the one command to run before a
# commit. It runs every tool in parallel and reports them together.
#
#     $ mix check          # run everything
#     $ mix check --retry  # rerun only the tools that failed last time
#     $ mix check --fix    # also apply fixes: `mix format`, `mix deps.unlock --unused`
#
# Besides the tools listed here, ex_check runs its defaults for whatever the
# project has: compiler, unused_deps, formatter, hex_audit, credo, ex_unit,
# gettext. See `mix help check`.
[
  # Always run every tool. Without this, a run after a failure silently reruns
  # only the tools that failed last time, so a problem introduced while fixing
  # another is missed. Pass --retry to opt in for one run.
  retry: false,
  # Do not list the tools that are skipped because their package is not
  # installed, such as dialyzer and sobelow. Pass --skipped to see them.
  skipped: false,
  tools: [
    # Custom source code checks in priv/checks, see `mix help app.checks`
    {:app_checks, "mix app.checks"}
  ]
]
