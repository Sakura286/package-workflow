---
name: grill-me
description: A relentless interview to sharpen a plan or design. Opt-in only — run ONLY when the user explicitly invokes it (e.g. `/grill-me` or "grill me"). Never auto-trigger it from the model, even when a task would seem to benefit from stress-testing a plan.
disable-model-invocation: true
---

## Language convention

Follow the repo-wide **Language** rule in `AGENTS.md` — put the questions to the
user in Chinese, keeping technical terms, code, paths, and error strings in their
original form.

## The grilling

Interview me relentlessly about every aspect of this plan until we reach a shared
understanding. Walk down each branch of the design tree, resolving dependencies
between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before
continuing. Asking multiple questions at once is bewildering.

If a *fact* can be found by exploring the codebase, look it up rather than asking
me. The *decisions*, though, are mine — put each one to me and wait for my answer.

Do not enact the plan until I confirm we have reached a shared understanding.
