#!/usr/bin/env bash
# PreToolUse(Write) guard: forbid hand-authoring a patch file under SPECS/.
#
# openRuyi packaging rule: patches must be tool-generated, never a hand-typed
# unified diff (line numbers/offsets are wrong ~70-80% of the time and then
# silently fail to apply in %prep). A brand-new .patch/.diff must come from one
# of the three routes in fix-build.md — download the upstream .patch, 'diff
# -Naur', or 'git format-patch' (all of which write via a Bash redirect, not
# the Write tool). Editing an already-generated patch to prepend its header is
# an Edit, not a Write, so it stays allowed.
#
# Contract: exit 2 => block (stderr fed back to Claude); otherwise exit 0.
set -u

input=$(cat)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[[ -z $fp ]] && exit 0

case "$fp" in
    */SPECS/*.patch|*/SPECS/*.diff)
        cat >&2 <<EOF
Refusing to Write a hand-authored patch:
  $fp
Patches must be tool-generated, not typed by hand. Produce it via one of the
fix-build.md routes, then Edit only to add the header:
  1. upstream artifact:  curl -L -o <NNNN>-<desc>.patch https://github.com/<org>/<repo>/commit/<sha>.patch
  2. diff tool:          cp -r src/<pkg> src/<pkg>.orig; ...edit...; diff -Naur src/<pkg>.orig src/<pkg> > <NNNN>-<desc>.patch
  3. git format-patch:   git -C src/<pkg> commit -am '<desc>'; git -C src/<pkg> format-patch -1 --stdout > <NNNN>-<desc>.patch
EOF
        exit 2
        ;;
esac
exit 0
