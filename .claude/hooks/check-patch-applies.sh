#!/usr/bin/env bash
# PostToolUse(Write|Edit) feedback gate: after a patch under SPECS/ is written
# or edited, dry-run it against the extracted source and inject the result back
# into the agent's context (additionalContext). The agent learns *immediately*
# whether a hand-adjusted diff actually applies at -p1, instead of discovering
# it hours later in an OBS %prep failure.
#
# PostToolUse cannot block (the write already happened) — it only injects
# feedback. Pairs with the PreToolUse guard that forbids hand-writing patches.
set -u

emit() {  # inject a note into the agent's context, then succeed
    jq -nc --arg c "$1" \
        '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    exit 0
}

input=$(cat)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[[ -z $fp ]] && exit 0
case "$fp" in
    */SPECS/*.patch|*/SPECS/*.diff) ;;
    *) exit 0 ;;
esac

ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
[[ -z $ROOT ]] && exit 0
[[ $fp = /* ]] || fp="$ROOT/$fp"
[[ -f $fp ]] || exit 0

pkg=$(sed -E 's#.*/SPECS/([^/]+)/[^/]+$#\1#' <<<"$fp")

# Locate the extracted source in src/: exact, case-insensitive, then a loose
# alias match after stripping a common python- prefix (python-triton -> triton).
find_src() {
    local d="$ROOT/src" m
    [[ -d $d/$1 ]] && { printf '%s\n' "$d/$1"; return; }
    m=$(find "$d" -maxdepth 1 -mindepth 1 -type d -iname "$1" 2>/dev/null | head -1)
    [[ -n $m ]] && { printf '%s\n' "$m"; return; }
    m=$(find "$d" -maxdepth 1 -mindepth 1 -type d -iname "*${1#python-}*" 2>/dev/null | head -1)
    [[ -n $m ]] && printf '%s\n' "$m"
}
src=$(find_src "$pkg")

if [[ -z $src ]]; then
    emit "Patch verify: could not find the extracted source for '$pkg' under src/, so $(basename "$fp") was not dry-run. Extract the tarball into src/ and confirm it applies at -p1 in %prep."
fi

# Prefer a pristine baseline (src/<pkg>.orig) when present; else the working tree.
base=$src
[[ -d ${src}.orig ]] && base=${src}.orig

if out=$( cd "$base" && git apply --check -p1 "$fp" 2>&1 ); then
    emit "Patch verify: $(basename "$fp") applies cleanly at -p1 against src/$(basename "$base"). (Checked in isolation — if it stacks on earlier PatchN, those must be applied first.)"
else
    emit "Patch verify: $(basename "$fp") does NOT apply at -p1 against src/$(basename "$base"):
${out}
Regenerate it with a tool — curl the upstream .patch, 'diff -Naur', or 'git format-patch' — never hand-edit hunks. Re-check with: (cd $base && git apply --check -p1 $fp)"
fi
