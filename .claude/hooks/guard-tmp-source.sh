#!/usr/bin/env bash
# PreToolUse(Bash) guard: forbid fetching/extracting *source* into /tmp.
#
# openRuyi packaging rule: upstream sources and tarballs live in src/ so they
# persist and are grep-able across sessions — never /tmp (see the
# openruyi-rocm-packaging skill). Transient test artifacts like /tmp/*.rpm are
# NOT source and stay allowed: this guard only trips on git clone, archive
# downloads, and tar extraction whose target is /tmp.
#
# Contract: exit 2 => block (stderr is fed back to Claude). Any other path,
# including internal errors, exits 0 (fail open) so a hook bug never wedges the
# session.
set -u

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -z $cmd ]] && exit 0

# Does the command reference a /tmp path (as a path token, not a substring)?
refs_tmp() { grep -Eq '(^|[[:space:]=>"'\''`(])/tmp(/|[[:space:]]|$)' <<<"$1"; }

# Archive extension anywhere in the command.
archive_re='\.(tar(\.(gz|xz|bz2|zst))?|tgz|tbz2|txz|zip)([[:space:]"'\''&|;>)]|$)'

reason=""
if grep -Eq '(^|[[:space:]])git([[:space:]]|$)' <<<"$cmd" && grep -Eq '(^|[[:space:]])clone([[:space:]]|$)' <<<"$cmd" && refs_tmp "$cmd"; then
    reason="git clone into /tmp is forbidden. Clone upstream sources into src/ (e.g. 'git clone --depth=1 --branch=rocm-<ver> <repo> src/<name>') so they persist and stay grep-able across sessions."
elif grep -Eq '(^|[[:space:]])(curl|wget)([[:space:]]|$)' <<<"$cmd" && refs_tmp "$cmd" && grep -Eiq "$archive_re" <<<"$cmd"; then
    reason="Downloading a source tarball into /tmp is forbidden. Save it under src/ (e.g. 'curl -fL -o src/<pkg>.tar.gz <url>') and keep the archive for cross-session reuse."
elif grep -Eq '(^|[[:space:]])tar([[:space:]]|$)' <<<"$cmd" && grep -Eq '\-C[[:space:]]*/tmp' <<<"$cmd"; then
    reason="Extracting a tarball into /tmp is forbidden. Extract under src/ (e.g. 'tar xf src/<pkg>.tar.gz -C src/') instead."
fi

if [[ -n $reason ]]; then
    printf '%s\n' "$reason" >&2
    exit 2
fi
exit 0
