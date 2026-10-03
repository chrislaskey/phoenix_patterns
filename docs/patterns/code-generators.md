# Code Generators

Use deterministic code generation tools whenever possible.

## Overview

One major issue with LLM output is its non-determinism. Instead rely on
deterministic code generators roughly in this order:

- Code generators that work with the abstract syntax tree (AST). Examples: `igniter`
- Code generators that rely on static analysis. Examples: `regex`

When writing SKILL files for LLMs, provide it with a library of deterministic
code generation tools and have it use those, rather than code examples and code
explanations.

## Implementation

**Key files**

- [hello.ex]()
- [world.ex]()

