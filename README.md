# Phoenix Patterns

> Patterns for delivering solutions in Phoenix in the age of LLMs

## Overview

Writing code has always been the fun part software engineers get to do in order
to deliver solutions to real problems. Modern software development is changing.

The way we've been building solutions - called the software development
life-cycle (or SDLC for short) - was refined over decades of lessons learned.
While tools have always been changing over those decades, none changed things
faster than the adoption of LLMs. That's because LLMs are changing the bigger
picture too, not just how we code itself is written, but how as a business
at large identifies and builds solutions to real problems.

It's a time of evolution and adaptation in how we write code. This repository
is a collection of patterns in-the-small that collectively add up to a better
and more streamlined way of shipping code.

It keeps humans where they are needed most - at the critical decision
making points. Abdicating decision making to LLMs is an anti-pattern.

While the patterns themselves are varied, this is one underlying theme that
runs through all of them - putting humans into charge of key decision making
and enabling LLMs to do the parts they excel at.

## The foundational assumption

Building a better software development process starts with accepting a
fundamental belief:

> Assume all code will contain mistakes

Regardless of who wrote it. LLMs make mistakes. Humans do too.

Modern software development is moving towards smaller teams that do more and
deliver faster. Experienced software engineers are writing code across more
areas and with less previous domain knowledge than ever before. Even without
using LLMs, the chances for mistakes has increased, not decreased.

## Patterns overview

Common themes in the patterns:

- Assume all code will contain mistakes. Use strict linters and tooling to speed up iteration cycles.
- Limit high-level architecture mistakes by keeping to simple core patterns and stricly enforce shared code follows them.
- Human in the loop is required for some aspects of code review. Full automation "fast lanes" for low-risk changes.
- Prototype in the app itself, not third party tools
- Do not merge protypes
- All code must be written with a functional deevelopment environment (any combination of local, docker, or cloud)

Common anti-patterns:

- LLMs can write good software with enough context and trust they'll build it correctly
- LLMs will make good architecture choices given enough context
- LLMs will follow a solid engineering plan without deviating from it

## 📚 Patterns Catalogue

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
