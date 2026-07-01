#!/usr/bin/env bash
# Stop hook: end-of-turn integrity gate for IN-PROGRESS spec changes. Before the
# turn ends, for each spec-repo package with UNCOMMITTED changes under SPECS/,
# it asserts three things and blocks (exit 2 -> the agent keeps working) only on
# CERTAIN failures:
#   1. every `PatchN: <file>` the spec references exists in the spec dir
#   2. if a pristine baseline src/<pkg>.orig exists, each PatchN applies at -p1
#   3. if exactly one matching Source tarball sits in src/, its sha256 matches
#      the spec's `#!RemoteAsset: sha256:` line
# Anything it cannot verify (no baseline, no/ambiguous tarball, source absent) is
# SKIPPED, never blocked — so it never wedges the workflow on uncertainty.
#
# Loop safety: Stop-hook exit 2 makes Claude continue, which can loop forever, so
# it no-ops when stop_hook_active is already set (docs' required guard).
set -u

input=$(cat)
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
[[ $active == true ]] && exit 0

ROOT=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
[[ -z $ROOT ]] && exit 0

problems=""
patch_refs() {  # emit the filenames referenced by PatchN: lines of a spec
    grep -oiE '^Patch[0-9]*:[[:space:]]*[^[:space:]]+' "$1" 2>/dev/null \
        | sed -E 's/^[^:]*:[[:space:]]*//'
}

check_spec() {  # <repo-dir> <pkg>
    local repo=$1 pkg=$2 specdir="$1/SPECS/$2" spec="$1/SPECS/$2/$2.spec"
    [[ -f $spec ]] || return
    local pf

    # 1) referenced patch files must exist
    while IFS= read -r pf; do
        [[ -z $pf ]] && continue
        [[ -f "$specdir/$pf" ]] || problems+=$'\n'"  [$pkg] spec references Patch '$pf' but $specdir/$pf is missing"
    done < <(patch_refs "$spec")

    # 2) apply-check only against a pristine baseline
    local base="$ROOT/src/${pkg}.orig"
    if [[ -d $base ]]; then
        while IFS= read -r pf; do
            [[ -z $pf || ! -f "$specdir/$pf" ]] && continue
            ( cd "$base" && git apply --check -p1 "$specdir/$pf" ) 2>/dev/null \
                || problems+=$'\n'"  [$pkg] Patch '$pf' does NOT apply at -p1 against src/${pkg}.orig"
        done < <(patch_refs "$spec")
    fi

    # 3) sha256 only when exactly one candidate tarball is present
    local sha
    sha=$(grep -oiE '#!RemoteAsset:[[:space:]]*sha256:[0-9a-fA-F]{64}' "$spec" | grep -oiE '[0-9a-fA-F]{64}' | head -1)
    if [[ -n $sha ]]; then
        local -a cands
        mapfile -t cands < <(find "$ROOT/src" -maxdepth 1 -type f \
            \( -iname "${pkg}*.tar*" -o -iname "${pkg}*.tgz" -o -iname "${pkg}*.zip" \) 2>/dev/null)
        if (( ${#cands[@]} == 1 )); then
            local got; got=$(sha256sum "${cands[0]}" | cut -d' ' -f1)
            [[ ${got,,} == "${sha,,}" ]] || problems+=$'\n'"  [$pkg] #!RemoteAsset sha256 ${sha,,} != sha256($(basename "${cands[0]}"))=${got}"
        fi
    fi
}

for repo in rocm-specs rocm-specs-7.2.4; do
    d="$ROOT/$repo"
    git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || continue
    while IFS= read -r pkg; do
        [[ -n $pkg ]] && check_spec "$d" "$pkg"
    done < <(git -C "$d" status --porcelain -- 'SPECS/*' 2>/dev/null \
        | grep -oE 'SPECS/[^/]+/' | sed -E 's#SPECS/([^/]+)/#\1#' | sort -u)
done

if [[ -n $problems ]]; then
    printf 'End-of-turn verification found unresolved issues in your in-progress spec changes:%s\n\nResolve them before finishing: regenerate broken patches with a tool, restore any missing patch file, or refresh the sha256 to match the tarball you downloaded.\n' "$problems" >&2
    exit 2
fi
exit 0
