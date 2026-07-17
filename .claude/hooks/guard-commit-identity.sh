#!/usr/bin/env bash
# PreToolUse(Bash) guard: spec repos must commit as CHEN Xuan.
#
# rocm-specs and openRuyi must commit as
# CHEN Xuan <chenxuan@iscas.ac.cn> — never as Claude or any other identity.
# Existing checkouts already have this git config; this guard catches a freshly
# cloned repo whose identity was never set, and an --author override that isn't
# CHEN Xuan.
#
# Contract: exit 2 => block (stderr fed back to Claude); otherwise exit 0.
set -u

EXPECT_EMAIL="chenxuan@iscas.ac.cn"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)
[[ -z $cmd ]] && exit 0

# Only act on an actual `git ... commit` (not log/show/reflog/--grep, whose
# args may merely contain the word "commit").
grep -Eq '(^|[[:space:]])git([[:space:]]|$)'    <<<"$cmd" || exit 0
grep -Eq '(^|[[:space:]])commit([[:space:]]|$)' <<<"$cmd" || exit 0
grep -Eq '(^|[[:space:]])(log|show|reflog)([[:space:]]|$)|--grep' <<<"$cmd" && exit 0

# Target repo: `git -C <dir>` if present, else the tool's cwd.
repo=""
if [[ $cmd =~ -C[[:space:]]+([^[:space:]]+) ]]; then
    repo=${BASH_REMATCH[1]}
else
    repo=$cwd
fi

case "$repo" in
    *rocm-specs*|*openRuyi*) ;;
    *) exit 0 ;;
esac

email=$(git -C "$repo" config user.email 2>/dev/null)
if [[ $email != "$EXPECT_EMAIL" ]]; then
    printf 'Commit blocked: %s is a spec repo that must commit as CHEN Xuan <%s>, but user.email is '\''%s'\''.\nSet it first:\n  git -C %s config user.name  "CHEN Xuan"\n  git -C %s config user.email %s\n' \
        "$repo" "$EXPECT_EMAIL" "${email:-unset}" "$repo" "$repo" "$EXPECT_EMAIL" >&2
    exit 2
fi

if grep -Eq -- '--author' <<<"$cmd" && ! grep -Eq 'chenxuan@iscas\.ac\.cn' <<<"$cmd"; then
    printf 'Commit blocked: an --author override on a spec repo must be CHEN Xuan <%s>.\n' "$EXPECT_EMAIL" >&2
    exit 2
fi
exit 0
