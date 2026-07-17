#!/usr/bin/env bash
# Install the tracked git hooks (scripts/git-hooks/) into the spec-repo clones
# by pointing each clone's core.hooksPath at this repo's git-hooks dir.
#
# This is a LOCAL git config change per clone (stored in .git/config, never
# pushed), so it enforces the commit-identity rule for every tool AND human on
# this machine without touching the shared GitHub repo. Re-run after cloning
# the workspace on a new machine. Uninstall with:
#   git -C <spec-repo> config --unset core.hooksPath
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && git rev-parse --show-toplevel)
HOOKS="$ROOT/scripts/git-hooks"

[[ -x "$HOOKS/pre-commit" ]] || { echo "error: $HOOKS/pre-commit missing or not executable" >&2; exit 1; }

for repo in rocm-specs openRuyi; do
    d="$ROOT/$repo"
    if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$d" config core.hooksPath "$HOOKS"
        echo "ok   $repo -> core.hooksPath = $HOOKS"
    else
        echo "skip $repo (not a git repo at $d)"
    fi
done
