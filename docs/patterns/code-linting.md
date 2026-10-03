# Code Linting

Provide deterministic tools to detect code mistakes. Make them run quickly.
Make them runnable locally.

## Overview

Assume code will not be correct the first time it's written. Invest in
tooling that can be run in the same local development environment. Make sure it
runs quickly. Make sure it covers the critical areas and gives meaningful
feedback/hints.

Use a combination of existing linting libraries along with custom checks. Speed
to run them is critical - slow linters will be ignored and eventually
discarded.

When possible use a tiered approach - have fast to execute checks that can
detect potential problems. Only if it flags specific issues, then run the
slower but more accurate tooling. For example, use static analysis (grep) to
find potential issues, then use a syntax parser (AST walking) to confirm the
flagged issues.

## Implementation

**Key files**

- [hello.ex]()
- [world.ex]()
