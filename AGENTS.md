# AGENTS.md — openRuyi Package Workflow

This repo maintains ROCm/PyTorch RPM specs for the openRuyi distribution.

## Skills

Specialized workflows live in `.claude/skills/`. Before starting work, check if
your task matches a skill by reading its frontmatter `description`:

| Skill | When to use |
|---|---|
| `openruyi-rocm-packaging` | Any ROCm spec task: add, upgrade, fix a build, reformat a `.spec`, trigger OBS, etc. |
| `rocm-llvm-bump` | ROCm build fails with LLVM/clang version-drift symptoms (missing static libs, gated builtins, relocated clang headers, API renames). Companion to `openruyi-rocm-packaging`. |

**To load a skill:** read `.claude/skills/<skill-name>/SKILL.md` in full, then
follow the workflow it describes.
