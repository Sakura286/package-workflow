#!/usr/bin/env bash
# watch-obs.sh — post-push watcher for an OBS build round.
#
# Polls the OBS API until every named package reaches a final state, emitting
# one stdout line per event. Designed to run under Claude Code's Monitor tool
# (each line becomes a notification that wakes the agent), but works
# standalone too.
#
# By default only the GATE row (amd64_build/x86_64) is tracked: riscv64 (which
# builds ~10x slower) is intentionally NOT watched, so the package finishes as
# soon as its x86_64 result lands — success or failure. Set GATE=none to watch
# every repo/arch in parallel instead.
#
# Usage:
#   watch-obs.sh <pkg> [pkg...]
#
# Env knobs:
#   POLL=60               seconds between status polls
#   TRIGGER_TIMEOUT=900   max seconds to wait for the pushed commit to appear
#   EXPECT_COMMIT=<sha>   commit the OBS service must pick up
#                         (default: current rocm-specs HEAD)
#   SKIP_TRIGGER_CHECK=1  skip the trigger phase — watch the current round
#                         as-is (ad-hoc, or resuming after a session restart)
#   GATE=repo/arch        gate row (default amd64_build/x86_64);
#                         GATE=none watches all rows in parallel
#
# Events (one per line on stdout):
#   TRIGGERED <pkg> <hash>             service picked up the pushed commit
#   TRIGGER-TIMEOUT <pkg> ...          commit never appeared (Actions run lost?)
#   RESULT <pkg> <repo>/<arch> <code>  a build row reached a final state
#   WARN ...                           anomaly (watch continues)
#   DONE <n> failed / <m> rows final   all watched rows final; watcher exits
#
# Exit code: 0 if no watched row failed, 1 otherwise. Slower arches (riscv64)
# are not watched by default — the x86_64 gate result is the whole round; the
# next push restarts it. Use GATE=none to watch all arches.

set -u

API=https://pickaxe.oerv.ac.cn
PRJ=home:Sakura286:ROCm_PyTorch_Submit
ROOT=~/Desktop/package-workflow
POLL=${POLL:-60}
TRIGGER_TIMEOUT=${TRIGGER_TIMEOUT:-900}
GATE=${GATE:-amd64_build/x86_64}

if (( $# < 1 )); then
    echo "usage: watch-obs.sh <pkg> [pkg...]" >&2
    exit 2
fi

# Final package codes. Everything else (scheduled, dispatching, building,
# finished, signing, blocked, locked, unknown, ...) means "still in progress".
is_final()   { [[ $1 =~ ^(succeeded|failed|unresolvable|broken|excluded|disabled)$ ]]; }
is_failure() { [[ $1 =~ ^(failed|unresolvable|broken)$ ]]; }

# Short commit hash currently in the package's expanded sources
# (from the obs_scm archive name: rocm-specs-<stamp>.<hash>.obscpio).
# `timeout` guards every osc call: a wedged HTTP connection must turn into a
# failed poll (retried next cycle), never a silent hang of the whole watch.
src_hash() {
    timeout 120 osc -A "$API" api "/source/$PRJ/$1?expand=1" 2>/dev/null \
        | grep -oE 'rocm-specs-[0-9]+\.[0-9a-f]+\.obscpio' | head -1 \
        | sed -E 's/rocm-specs-[0-9]+\.([0-9a-f]+)\.obscpio/\1/'
}

# CSV rows: "repo","arch","pkg","state","dirty","code","details"
rows()     { timeout 120 osc -A "$API" results "$PRJ" "$1" --csv 2>/dev/null; }
gate_row() { timeout 120 osc -A "$API" results "$PRJ" "$1" -r "${GATE%%/*}" -a "${GATE##*/}" --csv 2>/dev/null | head -1; }

EXPECT=${EXPECT_COMMIT:-$(git -C "$ROOT/rocm-specs" rev-parse HEAD)}

after_trigger=gate
[[ $GATE == none ]] && after_trigger=watch

declare -A PHASE STREAK PREV ROWFINAL GATE_EMPTY
for p in "$@"; do
    if [[ ${SKIP_TRIGGER_CHECK:-0} == 1 ]]; then PHASE[$p]=$after_trigger; else PHASE[$p]=trigger; fi
    GATE_EMPTY[$p]=0
done

deadline=$(( $(date +%s) + TRIGGER_TIMEOUT ))
fails=0 total=0 apierrs=0

# Parse one CSV line; declare the row once it reaches a stable final state.
# Requires two consecutive clean final reads: right after the service run the
# scheduler may not have flagged the rebuild yet, so a single stale
# "succeeded" must not count. Result is left in DECLARED_CODE ("" if the row
# is still in progress).
declare_row() {  # args: <pkg> <csv-line>
    local p=$1 line=$2 repo arch _pkg _state dirty code _rest key
    DECLARED_CODE=""
    line=${line//\"/}
    IFS=, read -r repo arch _pkg _state dirty code _rest <<<"$line"
    [[ -z $repo || -z $code ]] && return 1
    key=$p/$repo/$arch
    if [[ -n ${ROWFINAL[$key]:-} ]]; then
        DECLARED_CODE=${ROWFINAL[$key]}
        return 0
    fi
    if is_final "$code" && [[ $dirty == False ]]; then
        if [[ ${PREV[$key]:-} == "$code" ]]; then
            STREAK[$key]=$(( ${STREAK[$key]:-1} + 1 ))
        else
            STREAK[$key]=1
        fi
        if (( STREAK[$key] >= 2 )); then
            ROWFINAL[$key]=$code
            DECLARED_CODE=$code
            echo "RESULT $p $repo/$arch $code"
            total=$((total + 1))
            is_failure "$code" && fails=$((fails + 1))
        fi
    else
        STREAK[$key]=0
    fi
    PREV[$key]=$code
    return 0
}

while :; do
    for p in "$@"; do
        case ${PHASE[$p]} in
        done) ;;
        trigger)
            h=$(src_hash "$p")
            if [[ -n $h && ( $EXPECT == "$h"* || $h == "$EXPECT"* ) ]]; then
                echo "TRIGGERED $p $h"
                PHASE[$p]=$after_trigger
            elif (( $(date +%s) > deadline )); then
                echo "TRIGGER-TIMEOUT $p — commit ${EXPECT:0:7} not picked up after ${TRIGGER_TIMEOUT}s; re-trigger: osc -A $API service rr $PRJ $p"
                PHASE[$p]=done
                fails=$((fails + 1)); total=$((total + 1))
            fi
            ;;
        gate)
            out=$(gate_row "$p")
            if [[ -z $out ]]; then
                GATE_EMPTY[$p]=$(( GATE_EMPTY[$p] + 1 ))
                if (( GATE_EMPTY[$p] >= 5 )); then
                    echo "WARN no $GATE row for $p — watching all arches instead"
                    PHASE[$p]=watch
                fi
                continue
            fi
            GATE_EMPTY[$p]=0
            declare_row "$p" "$out" || continue
            if [[ -n $DECLARED_CODE ]]; then
                # Gate result (pass or fail) ends the round: riscv64 and any
                # other arches are not tracked by default (GATE=none opts in).
                PHASE[$p]=done
            fi
            ;;
        watch)
            out=$(rows "$p")
            if [[ -z $out ]]; then
                apierrs=$((apierrs + 1))
                if (( apierrs == 20 )); then
                    echo "WARN 20 consecutive failed status polls for $p — OBS API unreachable? Still watching."
                    apierrs=0
                fi
                continue
            fi
            apierrs=0
            pkgdone=1
            while IFS= read -r line; do
                declare_row "$p" "$line" || continue
                [[ -z $DECLARED_CODE ]] && pkgdone=0
            done <<<"$out"
            (( pkgdone )) && PHASE[$p]=done
            ;;
        esac
    done
    alldone=1
    for p in "$@"; do [[ ${PHASE[$p]} != done ]] && alldone=0; done
    (( alldone )) && break
    anytrig=0
    for p in "$@"; do [[ ${PHASE[$p]} == trigger ]] && anytrig=1; done
    if (( anytrig && POLL > 30 )); then sleep 30; else sleep "$POLL"; fi
done

echo "DONE $fails failed / $total rows final"
(( fails > 0 )) && exit 1
exit 0
