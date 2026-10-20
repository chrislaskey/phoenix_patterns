# Configuration for `mix app_checks`: the built-in checks and this project's
# own in priv/checks, in the shape of `.credo.exs`. See `mix help app_checks`
# for every key and the config of each check.
%{
  # This project's own checks, one .rs file each, compiled in with the
  # built-in ones. See docs/guides/writing-checks-in-rust.md
  custom_checks: "priv/checks",

  # `mix app_checks` runs the config called "default". Add another and run
  # it with `mix app_checks --config-name NAME`. Configs do not merge: each
  # one is the whole list for its run
  configs: [
    %{
      name: "default",
      # The git ref the branch is compared with, at the point the branch left
      # it. Only read, never fetched. `mix app_checks --base REF` overrides it
      # for one run, for a branch that builds on another branch
      base_ref: "origin/main",
      checks: [
        # A check runs only when it is listed here. An atom alone runs with
        # `level: :error` and `scope: :all`. `level: :warning` prints a
        # violation without failing the run. `scope: :changed` limits a check
        # to the files the branch changed, and the lines it changed in them,
        # so an old problem on a line the branch left alone is not reported.
        # `config:` holds the check's own keys
        enabled: [
          # Templates must use the component for any tag the components
          # modules define: `<.button>` instead of `<button>`, `<.input>`
          # instead of `<input>`. The tags are read from the modules, so adding
          # `def p` there is all it takes to start requiring `<.p>`. A new
          # application has nothing old to tolerate, so every file counts
          {:core_component_tags,
           config: [paths: ["lib/example_web/components/core_components.ex"]]},

          # Files that decide what gets checked or who reviews. A pull request
          # that changes a file in a group may change other files in the same
          # group and nothing else, so the change is the whole story and the
          # rules cannot be relaxed on the way past
          {:separate_pr,
           config: [
             groups: [
               agents: ["AGENTS.md"],
               codeowners: [".github/CODEOWNERS"],
               protected_workflows: [".github/workflows/protected-*.yml"],
               lint_config: [".credo.exs", ".check.exs", ".app_checks.exs"],
               checks: ["priv/checks/**"]
             ]
           ]},

          # Shared code, configuration and dependencies. A warning, so the run
          # says which files need an architect without failing. CODEOWNERS
          # requires the approval. Patterns match the whole path from the
          # project root: `*` does not cross a `/`, `**` does
          {:architect_review,
           level: :warning,
           config: [
             paths: [
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
               ".github/**",
               "Dockerfile",
               ".dockerignore",
               "docker/**",
               "bin/**",
               "rel/**"
             ]
           ]},

          # Feature work: contexts, schemas, LiveView modules, migrations and
          # tests. An engineer must review these. Templates and docs match
          # nothing here, so an automated reviewer alone can approve them
          {:human_review,
           level: :warning,
           config: [
             paths: [
               "lib/example/**",
               "lib/example_web/**/*.ex",
               "priv/repo/**",
               "priv/gettext/**",
               "test/**",
               "assets/**"
             ]
           ]}
        ],
        disabled: []
      ]
    }
  ]
}
