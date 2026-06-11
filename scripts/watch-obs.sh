#!/usr/bin/env bash
# watch-obs.sh — post-push watcher for an OBS build round.
#
# Polls the OBS API until every named package reaches a final state on every
# repo/arch it builds for, emitting one stdout line per event. Designed to run
# under Claude Code's Monitor tool (each line becomes a notification that wakes
# the agent), but works standalone too.
#
# Usage:
#   watch-obs.sh <pkg> [pkg...]
#
# Env knobs:
#   POLL=60               seconds between status polls (phase 2)
#   TRIGGER_TIMEOUT=900   max seconds to wait for the pushed commit to appear
#   EXPECT_COMMIT=<sha>   commit the OBS service must pick up
#                         (default: current rocm-specs HEAD)
#   SKIP_TRIGGER_CHECK=1  skip phase 1 — watch current state as-is
#
# Events (one per line on stdout):
#   TRIGGERED <pkg> <hash>             service picked up the pushed commit
#   TRIGGER-TIMEOUT <pkg> ...          commit never appeared (Actions run lost?)
#   RESULT <pkg> <repo>/<arch> <code>  one build row reached a final state
#   WARN ...                           repeated API failures (watch continues)
#   DONE <n> failed / <m> rows final   all rows final; watcher exits
#
# Exit code: 0 if no row failed (succeeded/excluded/disabled only), 1 otherwise.

set -u

API=https://pickaxe.oerv.ac.cn
PRJ=home:Sakura286:ROCm_PyTorch_Submit
ROOT=~/Repo/package-workflow
POLL=${POLL:-60}
TRIGGER_TIMEOUT=${TRIGGER_TIMEOUT:-900}

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
src_hash() {
    osc -A "$API" api "/source/$PRJ/$1?expand=1" 2>/dev/null \
        | grep -oE 'rocm-specs-[0-9]+\.[0-9a-f]+\.obscpio' | head -1 \
        | sed -E 's/rocm-specs-[0-9]+\.([0-9a-f]+)\.obscpio/\1/'
}

# CSV rows for one package: "repo","arch","pkg","state","dirty","code","details"
rows() { osc -A "$API" results "$PRJ" "$1" --csv 2>/dev/null; }

EXPECT=${EXPECT_COMMIT:-$(git -C "$ROOT/rocm-specs" rev-parse HEAD)}

declare -A PHASE STREAK PREV ROWFINAL
for p in "$@"; do
    if [[ ${SKIP_TRIGGER_CHECK:-0} == 1 ]]; then PHASE[$p]=watch; else PHASE[$p]=trigger; fi
done

deadline=$(( $(date +%s) + TRIGGER_TIMEOUT ))
fails=0 total=0 apierrs=0

while :; do
    alldone=1
    for p in "$@"; do
        case ${PHASE[$p]} in
        done) ;;
        trigger)
            alldone=0
            h=$(src_hash "$p")
            if [[ -n $h && ( $EXPECT == "$h"* || $h == "$EXPECT"* ) ]]; then
                echo "TRIGGERED $p $h"
                PHASE[$p]=watch
            elif (( $(date +%s) > deadline )); then
                echo "TRIGGER-TIMEOUT $p — commit ${EXPECT:0:7} not picked up after ${TRIGGER_TIMEOUT}s; re-trigger: osc -A $API service rr $PRJ $p"
                PHASE[$p]=done
                fails=$((fails + 1)); total=$((total + 1))
            fi
            ;;
        watch)
            out=$(rows "$p")
            if [[ -z $out ]]; then
                alldone=0
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
                line=${line//\"/}
                IFS=, read -r repo arch _pkg _state dirty code _rest <<<"$line"
                [[ -z $repo || -z $code ]] && continue
                key=$p/$repo/$arch
                [[ -n ${ROWFINAL[$key]:-} ]] && continue
                # Require two consecutive clean final reads: right after the
                # service run the scheduler may not have flagged the rebuild
                # yet, so a single stale "succeeded" must not count.
                if is_final "$code" && [[ $dirty == False ]]; then
                    if [[ ${PREV[$key]:-} == "$code" ]]; then
                        STREAK[$key]=$(( ${STREAK[$key]:-1} + 1 ))
                    else
                        STREAK[$key]=1
                    fi
                    if (( STREAK[$key] >= 2 )); then
                        ROWFINAL[$key]=$code
                        echo "RESULT $p $repo/$arch $code"
                        total=$((total + 1))
                        is_failure "$code" && fails=$((fails + 1))
                    else
                        pkgdone=0
                    fi
                else
                    STREAK[$key]=0
                    pkgdone=0
                fi
                PREV[$key]=$code
            done <<<"$out"
            if (( pkgdone )); then PHASE[$p]=done; else alldone=0; fi
            ;;
        esac
    done
    (( alldone )) && break
    # poll faster while still waiting for a trigger to land
    anytrig=0
    for p in "$@"; do [[ ${PHASE[$p]} == trigger ]] && anytrig=1; done
    if (( anytrig && POLL > 30 )); then sleep 30; else sleep "$POLL"; fi
done

echo "DONE $fails failed / $total rows final"
(( fails > 0 )) && exit 1
exit 0
