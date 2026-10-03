# Code Review

Tier code reviews - make a "fast lane" for low-risk changes with simpler review
standards. Increase approval standards for high-risk changes.

## Overview

Create "fast lanes" for low-risk changes. 

For example, updating the UI of an existing feature 
in a `heex` template file might

For example, changing HTML in a `heex` file for a specific page 

Increase review
standards for core logic, code architecture, and code changes.



Lower review standards for low-risk changes. High review standards for high-risk and architecture changes.

Tier the code review processso low-risk changes

- Code review tiers. Prevent privilege escalation by requiring a human with a software architect role to review
changes to rules and LLM generation files like AGENTS.md.
- Require changes to privileged files to be done in separate PRs for historical record and accountability (no mixing AGENTS.md change and a UI fix in the same PR)
