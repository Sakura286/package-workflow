# AGENTS.md — openRuyi Package Workflow

This repo maintains ROCm/PyTorch RPM specs for the openRuyi distribution.

## Core rules (all agents)

These invariants apply to **every** agent working in this repo (Claude Code,
mimo code, opencode, codebuddy, …) and to humans. They are the same rules the
skills teach; they live here so no agent has to load a skill to know them.

- **Commit identity.** The spec repos — `rocm-specs`, `rocm-specs-7.2.4`,
  `openRuyi` — must commit as **`CHEN Xuan <chenxuan@iscas.ac.cn>`**, never as
  the agent or any other identity. One package per commit. Subject style is
  per-repo: `rocm-specs`/`rocm-specs-7.2.4` (private dev repos) take a one-line
  lowercase `<pkg>: <short desc>`; `openRuyi` is the official distro repo —
  follow its own conventions there (e.g. `SPECS: <pkg>: Update to <ver>`), not
  ours. (A `pre-commit` hook enforces the identity — install it once with
  `scripts/install-git-hooks.sh`.)
- **Sources live in `src/`, never `/tmp`.** Clone or download upstream sources
  and tarballs into `src/` (grep-able and reused across sessions); keep the
  tarball after extracting. Never fetch or extract source into `/tmp`.
- **Scratch files live in `tmp/`, never the host `/tmp`.** Any transient file an
  agent creates — build/query scripts, RPMs pulled from OBS, intermediate
  outputs, logs — goes under the workspace-local `tmp/` (gitignored, kept across
  sessions), not the host `/tmp`, which parallel agents share and clobber.
  (Sole exception: the session scratchpad directory that the Claude Code
  harness itself provides and manages, outside the workspace — files the
  harness puts there may stay there; every file an agent places by its own
  choice goes in `tmp/`.) Paths *inside* the QEMU VM such as `openruyi@localhost:/tmp/` are the
  guest's own filesystem and stay as-is.
- **Patches must be tool-generated.** Never hand-write a unified diff — download
  the upstream `.patch`, or use `diff -Naur`, or `git format-patch`; then edit
  only to add the header. Number by origin: `0001-0999` same-version upstream,
  `1000-1999` backport from another version, `2000-2999` openRuyi-specific.
- **Run commands from the workspace root** (`package-workflow/`); all paths are
  relative to it.
- **`gh` fetches, it doesn't publish.** Use the `gh` CLI only to *read* — pull
  down a PR, issue, source, or CI status. Never proactively open a PR or issue
  (or push a branch to raise one); deliver changes as commits and let the user
  open one if they want it.

Claude Code additionally enforces commit identity, the sources rule, and
patches at tool-call time via `.claude/settings.json` hooks; the remaining rules
are convention only (the sources hook blocks *source* into `/tmp`, not scratch).
Other agents should honor all of them by convention.

## Working principles (all agents)

Behavioural rules that back up the hard rules above. They matter here because a
wrong guess usually costs an hour-long OBS rebuild to surface.

- **Language.** Prefer English for technical analysis, but reason directly from
  source material in its original language when translation could lose meaning
  or context. Reply to the user in Chinese; keep technical terms, code, paths,
  and error strings in their original form. Call out material translation
  ambiguities instead of silently choosing an interpretation.
- **Verify, don't fabricate.** Never invent a commit SHA, upstream PR number,
  version, target-feature, sha256, or file path. If you can't confirm it from
  the source tree, a tool, or the web, say so and stop. (Clone the upstream tag
  into src/ and grep it; read the actual build log, not the spec's comments.)
- **Research before guessing.** For an unfamiliar error/API/version, search the
  upstream issues/PRs/commits and official docs before writing a fix — prefer
  them over training data, which lags the code.
- **Read before you edit.** Read enough of the spec / CMakeLists / log to
  understand it; don't act on partial understanding or on what a comment claims.
- **Surgical changes.** Touch only what the task needs; match the file's style;
  don't reformat or "improve" unrelated parts of a spec.
- **Candor.** Push back with specific reasons when a request looks wrong; don't
  affirm a false premise or drop a correct position under pressure.

## Skills

Specialized workflows live in `.claude/skills/`. Before starting work, check if
your task matches a skill by reading its frontmatter `description`:

| Skill | When to use |
|---|---|
| `openruyi-rocm-packaging` | Any ROCm spec task: add, upgrade, fix a build, reformat a `.spec`, trigger OBS, etc. |
| `llvm-drift` | ROCm build fails with LLVM/clang version-drift symptoms (missing static libs, gated builtins, relocated clang headers, API renames). Companion to `openruyi-rocm-packaging`. |
| `grill-me` | **Only when the user explicitly asks for it** (`/grill-me`, "grill me", or a direct request to be grilled). A relentless plan/design interview. Never auto-trigger it — not even when a task would obviously benefit from stress-testing a plan. |

**To load a skill:** read `.claude/skills/<skill-name>/SKILL.md` in full, then
follow the workflow it describes.

## Deferred work (`todo/`)

`todo/` holds one Markdown file per **known-but-deferred** issue — a real bug or
task we consciously chose not to fix in the moment, written up so a later agent
(or human) can pick it up cold. Each file states the symptom, what has already
been ruled out, an exact reproduction, and the next steps to try. Before
starting related work, skim `todo/` for an existing writeup; when you defer
something non-trivial, add one there (and delete it once resolved).
