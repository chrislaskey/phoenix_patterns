# Phoenix Patterns

> Patterns for working with Phoenix in the age of LLMs

## Overview

Modern software development is moving towards smaller teams that do more and
deliver faster. In practice this may mean a combination of solving for:

In practice, this means code contributions will come from:

- Software engineers. Smaller teams, ownership over more areas with less domain knowledge than before. Even hand written code will contain more mistakes than in the past.
- Non-technical contributors. Product, design, sales, all contributing and building features using LLMs

- Software engineers using LLM agents / loops.

- Higher software development - rapid prototyping, demos, fast delivery important
- Faster speed of delivery - automating testing, automating aspects of code reviews, post-deploy validation

As well as realities that code will be generated:

- With a human in the loop. 
- With no human in the loop (agents).

The patterns in this library are shared learnings from adapting to this new normal.

Common anti-patterns I've seen but don't believe is true:

- Assume LLMs can write good software with enough context and trust they'll build it correctly
- Assume LLMs will make good architecture choices given enough context
- LLMs will deliver correct code if given a solid engineering plan

The patterns in this library are shared learnings from adapting to this new normal.

- Assume all code will contain mistakes. Use strict linters and tooling to speed up iteration cycles.
- Limit high-level architecture mistakes by keeping to simple patterns and enforce adherence strictly
- Human in the loop is required for some aspects of code review. Full automation "fast lanes" for low-risk changes.
- Prototype in the app itself, not third party tools
- Do not merge protypes
- All code must be written with a functional deevelopment environment (any combination of local, docker, or cloud)

## 📚 Patterns

- [Code Linting](docs/patterns/code-linting.md)
- [Code Review](docs/patterns/code-review.md)
- [Code Generators](docs/patterns/code-generators.md)
- [Common UI](docs/patterns/common-ui.md)
- [Prototypes](docs/patterns/prototypes.md)

## Quick start

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
* Run `mix check` before committing, it runs every linter, the tests, and the custom checks

Now you can visit [`localhost:4010`](http://localhost:4010) from your browser.
