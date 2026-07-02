#!/usr/bin/env bash
# sync-openruyi-obs.sh — daily sync of the read-only openRuyi OBS checkout.
#
# Runs `osc up` inside openruyi-obs/ to pull the latest state of the official
# openRuyi OBS project ("openruyi" on https://pickaxe.oerv.ac.cn). That checkout
# is read-only to us — a reference for how the shipping distro packages things;
# we never commit to it. Installed as a user cron job that fires at 11:00
# Asia/Shanghai daily, but also safe to run by hand.
#
#   crontab entry:
#   0 11 * * * /home/infinity/Desktop/package-workflow/scripts/sync-openruyi-obs.sh
#
# Output (stdout+stderr, timestamped) is appended to log/openruyi-obs-sync.log.
set -uo pipefail

# Repo root, derived from this script's own location — no hardcoded paths, and
# robust to cron's bare working directory.
ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OBS_DIR="$ROOT/openruyi-obs"
LOG="$ROOT/log/openruyi-obs-sync.log"

# cron runs with a minimal PATH; make sure osc (/usr/bin/osc) is found.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

mkdir -p "$ROOT/log"

rc=0
{
    echo "===== $(date '+%F %T %Z') osc up in $OBS_DIR ====="
    if cd "$OBS_DIR"; then
        osc up
        rc=$?
    else
        echo "ERROR: cannot cd into $OBS_DIR" >&2
        rc=1
    fi
    echo "----- osc up exit $rc -----"
} >>"$LOG" 2>&1

exit "$rc"
