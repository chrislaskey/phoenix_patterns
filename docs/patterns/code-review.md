# Code Review

Tier code reviews - make a "fast lane" for low-risk changes with simpler review
standards. Increase approval standards for high-risk changes.

## Overview

It's best to assume all code generated will contain mistakes, regardless of
the source. [Code Linting](../code-linting.md) lets the code writer detect
issues and fix them locally before asking for code review by peers.

Code review by peers should also have a robust series of checks. Automated code
review should run quickly and provide meaningful feedback. These ensure they
continue to be used, instead of replaced or removed.

Which checks are enabled in code review should be a sliding scale depending on
risk.

This tiered approach creates a natural "fast lane" for low-risk changes, and a
thoughtful review loop for higher-risk larger more impactful changes. While the
actual tiers themselves can be customized to the particular app, this pattern
introduces three main levels that should work for most:

- low-risk
- standard-risk
- high-risk

Code analysis runs to determine which bucket these are in, allowing apps to map
each one to a separate authorization mechanism. These are mapped to GitHub
CODEOWNERS for illustration, but the tier ranking is generic, making it easy to
hook into a different paradigm as needed.

For example, these might map to:

- low-risk: small UI change, reviewable by Non-technical engineers or LLMs
- standard-risk. full feature, reviewable by any human engineer
- high-risk. core architecture changes, reviewable by human software architects

Finally, there is a fourth type, called `protected`. This special type is primarily used
for application configuration and rulesetting. Changes to protected files must
be done in separate stand-alone Pull Requests without any other changes.
Protected files includes configuration and rules, which prevents the most
common kind of privilege escalation (changing the rules to make them more relaxed).

Protect is important to have so code review checks cannot get easily
circumvented. 

## Implementation

Three small checks in the `rust` linter decide the review a branch needs,
and they run as part of the unified `mix check` command, so the answer is
the same locally and in CI. Each one does one thing, and `.app_checks.exs`
says what a hit means:

- `separate_pr` is the `protected` rule. Files are listed in named groups,
  and a pull request that changes a file in a group may change other
  files in the same group and nothing else. It is an `error`, so the run
  fails until the change stands alone.
- `architect_review` lists the high-risk paths. A hit is a `warning` that
  says which files need an architect, so the run prints them without
  failing. CODEOWNERS requires the approval.
- `human_review` lists the standard-risk paths an engineer must read. A
  hit is a `warning` too. Paths that match neither list are low-risk, and
  an automated reviewer alone can approve them.

The three lists may overlap, and the reader sees every hit. A warning is
information for the people and tools reading the pull request. An error
blocks it. Both labels are set in the config, not in the checks.

GitHub Actions workflow is also included, showing how these checks can be
integrated end-to-end.

Note: The branch is compared with `origin/main` by default, which is
`base_ref` in `.app_checks.exs`. An alternative base branch can be passed
using the `--base` flag:

```sh
mix app_checks --base feature/parent-branch
```

**Key files**

- [The separate pull request check](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/separate_pr.rs)
- [The architect review check](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/architect_review.rs)
- [The human review check](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/human_review.rs)
- [The config that lists the paths of each](../../.app_checks.exs)
- [The Mix task that runs them](https://github.com/chrislaskey/app_checks/blob/main/lib/mix/tasks/app_checks.ex)
- [Who approves each path](../../.github/CODEOWNERS)
- [The CI workflow that runs `mix check`](../../.github/workflows/protected-check.yml)

### Concrete examples

| Risk | Examples | Who reviews | Check |
|---|---|---|---|
| low | Templates under `lib/app_web/live/`, docs | An automated reviewer | Matches neither list |
| standard | Contexts, schemas, LiveView modules, tests, migrations | An engineer | `human_review`, a warning |
| high | `lib/app_web.ex`, `lib/app_web/components/`, `config/`, `mix.exs` | An architect | `architect_review`, a warning |
| protected | `AGENTS.md`, `CODEOWNERS`, the lint and check config, the checks themselves, the CI workflows that enforce this | An architect | `separate_pr`, an error: must be the only change in the pull request |

## Adopting this pattern

1. Adopt the [Code Linting](code-linting.md) pattern first. The three
   review checks are built into the library it installs.
2. Edit the `separate_pr`, `architect_review` and `human_review` entries
   in `.app_checks.exs`. Start from the one here and rename `app`.
   List every path that needs an engineer under `human_review`, since a
   path that matches nothing is treated as low-risk.
3. Run `mix app_checks` on a feature branch and read the lines. Move paths
   between the lists until the warnings match what you would ask for by
   hand.
4. Copy `.github/CODEOWNERS`, rename `app` and the teams, and turn on
   the branch ruleset: one approval, review from code owners, and the
   `mix check` status check required.
5. Copy `.github/workflows/protected-check.yml`. Nothing in it is named
   after the application.
