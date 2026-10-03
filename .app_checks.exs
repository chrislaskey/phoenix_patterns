# Configuration for `mix app.checks`, the custom source code checks in
# priv/checks. Every key is optional. These are the defaults, so this file can
# be deleted without changing anything. See `mix help app.checks`.
[
  # Files and directories to scan when none are given on the command line
  paths: ["lib"],
  # Directory names skipped wherever they appear under those paths
  paths_to_ignore: ["_build", "deps", "node_modules"],
  # Every file in priv/checks/src/checks is a check unless it is named here,
  # for example `[:raw_html_tags]`
  disabled_checks: []
]
