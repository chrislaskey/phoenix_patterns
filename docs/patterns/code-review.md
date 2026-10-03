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

The tier check itself is built into the `rust` linter that gets run as part of
the unified `mix check` command. This way it can be run both locally in a code
linting stage and later in an automated CI stage. The highest tier is always
returned.

GitHub Actions workflow is also included, showing how these checks can be
integrated end-to-end.

Note: The branch is compared with `origin/main` by default. An alternative base branch
can be passed using the `--base` flag:

```sh
mix app.checks --base feature/parent-branch
```

**Key files**

- [The review tier check](../../priv/checks/src/checks/review_tier.rs)
- [The review tier config for every tier](../../.app_checks.exs)
- [The Mix task that runs it](../../lib/mix/tasks/app.checks.ex)
- [Who approves each path](../../.github/CODEOWNERS)
- [The CI workflow that runs `mix check`](../../.github/workflows/protected-check.yml)

### Concrete examples

| Tier | Examples | Who reviews | Extra rule |
|---|---|---|---|
| `low` | Templates under `lib/example_web/live/`, docs | An automated reviewer | |
| `standard` | Contexts, schemas, LiveView modules, tests, migrations | An engineer | |
| `high` | `lib/example_web.ex`, `lib/example_web/components/`, `config/`, `mix.exs`, anything no rule covers | An architect | |
| `protected` | `AGENTS.md`, `CODEOWNERS`, the lint and check config, the checks themselves, the CI workflows that enforce this | An architect | Must be the only change in the pull request |

## Adopting this pattern

1. Adopt the [Code Linting](code-linting.md) pattern first. The tier check
   is one of the custom checks it runs.
2. Edit the `review_tier` key in `.app_checks.exs`. Start from the one here
   and rename `example`. Keep `default: :high` so a path you forgot asks for
   more review, not less.
3. Run `mix app.checks` on a feature branch and read the lines. Move paths
   between tiers until the tier matches what you would ask for by hand.
4. Copy `.github/CODEOWNERS`, rename `example` and the teams, and turn on
   the branch ruleset: one approval, review from code owners, and the
   `mix check` status check required.
5. Copy `.github/workflows/protected-check.yml`. Nothing in it is named
   after the application.
