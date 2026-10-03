# Configuration for `mix app.checks`, the custom checks in priv/checks. The
# first four keys are the runner's and are optional with these defaults.
# Every other key names a check and holds its settings. See
# `mix help app.checks`.
[
  # Files and directories the source checks scan when none are given on the
  # command line
  paths: ["lib"],
  # Directory names skipped wherever they appear under those paths
  paths_to_ignore: ["_build", "deps", "node_modules"],
  # Every file in priv/checks/src/checks is a check unless it is named here,
  # for example `[:core_component_tags]`
  disabled_checks: [],
  # What the branch checks compare the current branch with, at the point the
  # branch left it. Only read, never fetched. `mix app.checks --base REF`
  # overrides it for one run, for a branch that builds on another branch.
  base: "origin/main",

  # Templates must use the component for any tag the components modules
  # define: `<.button>` instead of `<button>`, `<.input>` instead of
  # `<input>`. The tags are read from the modules, so adding `def p` there is
  # all it takes to start requiring `<.p>`.
  core_component_tags: [
    # The components modules, one or several when the design system spans
    # files. Without this key, the one core_components.ex under lib.
    paths: ["lib/example_web/components/core_components.ex"]
  ],

  # Which review a branch needs, from the paths it changed. A path is tested
  # against the tiers from protected down to low and the first match wins, so
  # a broad low pattern cannot pull a file out of a higher tier. Patterns
  # match the whole path from the project root: `*` does not cross a `/`,
  # `**` does.
  review_tier: [
    # Tier for paths that match no pattern below: :high or :standard
    default: :high,

    # Files that decide what gets checked or who reviews. A pull request that
    # changes any file in a group may change other files in the same group
    # and nothing else. Reviewed by an architect.
    protected: [
      agents: ["AGENTS.md"],
      codeowners: [".github/CODEOWNERS"],
      protected_workflows: [".github/workflows/protected-*.yml"],
      lint_config: [".credo.exs", ".check.exs", ".app_checks.exs"],
      checks: ["priv/checks/**", "lib/mix/tasks/app.checks.ex"]
    ],

    # Shared code, configuration and dependencies. Reviewed by an architect.
    high: [
      "lib/example_web.ex",
      "lib/example_web/components/**",
      "lib/example_web/router.ex",
      "lib/example_web/endpoint.ex",
      "lib/example/application.ex",
      "priv/code_generators/**",
      "config/**",
      "mix.exs",
      "mix.lock",
      ".tool-versions",
      "test/support/**",
      ".github/**"
    ],

    # Feature work. Reviewed by an engineer.
    standard: [
      "lib/example/**",
      "lib/example_web/**/*.ex",
      "priv/repo/**",
      "priv/gettext/**",
      "test/**",
      "assets/**"
    ],

    # Templates and docs. Reviewed by an automated reviewer.
    low: [
      "lib/example_web/live/**/*.heex",
      "lib/example_web/controllers/**/*.heex",
      "docs/**",
      "README.md"
    ]
  ]
]
