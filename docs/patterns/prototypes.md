# Prototypes

Make it easy and fast to generate prototypes in the same application. Do not merge them.

## Overview

Protypes are enormously helpful and there are many tools to build them outside
of the app code itself. While these work, in practice the distance from in-app
code causes a variety of friction points:

- Demo environments make assumptions about in-app code. This can lead to
solutions that require large changes rather than hooking into existing patterns
with minimal additional code in both UI, backend, and data layers.
- UI/UX drift and false approximations of existing UI. This leads to
implementation confusion - is the button padding wider because it's a concious
choice and part of the requirements? Or is it just a generation mistake while
simulating the existing UI?
- Simulated backends and data layers. Most prototypes only go as deep as the UX flow
and simulate backends and data layers. Does this reuse existing patterns or
implement new ones?
- Prototype graveyards. After prototypes are built, they often hang around
in the third-party tool. Which of these are complete, which are still outstanding?

This pattern is about moving prototypes to be done in-app. An in-app prototype
can match all of the functionality of third-party tools while also solving:

- UI/UX alignment. Using real component library vs. a mock one in prototypes.
- Gap identification. Clearly shows what is reusable, and what still needs to
be built before the prototype is turned into production code.

Add in Docker and automatic code watching, and now these in-app prototypes can also provide:

- Demoable environments that can be viewed by others
- Multi-user collaborative real-time development (using code watchers/automatic rebuild tooling in Docker)
- Easy automation for code review (screenshots, videos)

Additional points:

- Do not allow prototypes to be merged. Have CI checks prevent this. Instead
make them easily deployable. Can be validated against, even bringing in the
prototype code into the PR while it's being built. But when it's delivered,
only the feature exists and not the prototype.

## Implementation

Use docker builds that contain the full release environment. Add in opt-in
GITHUB watchers to detect changes.

**Key files**

- [hello.ex]()
- [world.ex]()
