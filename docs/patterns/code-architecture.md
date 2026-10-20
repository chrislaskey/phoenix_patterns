# Code Architecture

- Set core patterns and ensure everything uses them.
- Better to repeat code instead of breaking core patterns

Better to have hundreds of self contained features with code duplication that
are properly bounded than competing core patterns.

Push all LLM changes down to the leaf nodes.

## Implementation

- `boundary` library
- Tiered code-review (see code-review.md guide)
- Simple core design patterns with checkers to ensure they all follow the same patterns
- Low level contexts for Repo interactions
- No `Repo.all` in the lib/example_web/live directories?
