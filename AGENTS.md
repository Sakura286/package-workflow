# AGENTS.md — openRuyi Package Workflow

This repo maintains ROCm/PyTorch RPM specs for the openRuyi distribution.

## Core rules (all agents)

These invariants apply to **every** agent working in this repo (Claude Code,
mimo code, opencode, codebuddy, …) and to humans. They are the same rules the
skills teach; they live here so no agent has to load a skill to know them.

- **Commit identity.** The spec repos — `rocm-specs`, `rocm-specs-7.2.4`,
  `openRuyi` — must commit as **`CHEN Xuan <chenxuan@iscas.ac.cn>`**, never as
  the agent or any other identity. One package per commit; one-line lowercase
  subject `<pkg>: <short desc>`. (A `pre-commit` hook enforces this — install it
  once with `scripts/install-git-hooks.sh`.)
- **Sources live in `src/`, never `/tmp`.** Clone or download upstream sources
  and tarballs into `src/` (grep-able and reused across sessions); keep the
  tarball after extracting. Never fetch or extract source into `/tmp`.
- **Patches must be tool-generated.** Never hand-write a unified diff — download
  the upstream `.patch`, or use `diff -Naur`, or `git format-patch`; then edit
  only to add the header. Number by origin: `0001-0999` same-version upstream,
  `1000-1999` backport from another version, `2000-2999` openRuyi-specific.
- **Run commands from the workspace root** (`package-workflow/`); all paths are
  relative to it.

Claude Code additionally enforces the first three at tool-call time via
`.claude/settings.json` hooks; other agents should honor them by convention.

## Working principles (all agents)

Behavioural rules that back up the hard rules above. They matter here because a
wrong guess usually costs an hour-long OBS rebuild to surface.

- **Language.** Think and reason in English; reply to the user in Chinese; keep
  technical terms, code, paths, and error strings in English (don't translate).
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
| `rocm-llvm-bump` | ROCm build fails with LLVM/clang version-drift symptoms (missing static libs, gated builtins, relocated clang headers, API renames). Companion to `openruyi-rocm-packaging`. |

**To load a skill:** read `.claude/skills/<skill-name>/SKILL.md` in full, then
follow the workflow it describes.
