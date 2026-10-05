#!/bin/bash
# Print fan speed, CPU temperature and available memory for a tmux status bar,
# e.g. "FAN1785 CPU59C RAM39G" (fan rpm, CPU degrees C, available RAM GiB).
# Plain ASCII on purpose: symbol glyphs rendered inconsistently in the status bar.
#
# All three are gathered in one pass and cached for POLL_SECONDS, so this stays
# cheap even though tmux redraws the status bar every second (status-interval 1,
# which the seconds in the clock depend on).

POLL_SECONDS=10
CACHE="${TMPDIR:-/tmp}/smc_fan_status"
BIN="$(cd "$(dirname "$0")" && pwd)/build/smc_fan_util"

if [ -f "$CACHE" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))

    if [ "$age" -lt "$POLL_SECONDS" ] && [ "$age" -ge 0 ]; then
        cat "$CACHE"
        exit 0
    fi
fi

rpm=$("$BIN" -i 2>/dev/null | awk '/Actual speed/ { print $4; exit }')
[ -z "$rpm" ] && rpm="?"

temp=$("$BIN" -t 2>/dev/null | awk '{ printf "%.0f", $1 }')
[ -z "$temp" ] && temp="?"

# "Available" rather than strictly free: on macOS the inactive, speculative and
# purgeable pages are all reclaimable on demand, and raw "Pages free" badly
# understates usable memory once the file cache has warmed up.
mem=$(vm_stat | awk '
    /page size of/            { for (i = 1; i <= NF; i++) if ($i == "of") { pagesize = $(i + 1); break } }
    /^Pages free/             { gsub(/\./, "", $NF); pages += $NF }
    /^Pages inactive/         { gsub(/\./, "", $NF); pages += $NF }
    /^Pages speculative/      { gsub(/\./, "", $NF); pages += $NF }
    /^Pages purgeable/        { gsub(/\./, "", $NF); pages += $NF }
    END { if (pagesize > 0) printf "%.0f", pages * pagesize / 1073741824 }
')
[ -z "$mem" ] && mem="?"

# write atomically so a concurrent reader never sees a half-written file
printf 'FAN%s CPU%sC RAM%sG ' "$rpm" "$temp" "$mem" > "$CACHE.$$" && mv -f "$CACHE.$$" "$CACHE"
cat "$CACHE"
