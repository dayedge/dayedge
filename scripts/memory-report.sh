#!/bin/bash
# DayEdge memory report — one command, the same detailed report every time.
#
#   scripts/memory-report.sh                  measure the running DayEdge
#   scripts/memory-report.sh --launch         quit it, launch build/DayEdge.app fresh, settle, measure
#   scripts/memory-report.sh --stacks         like --launch, with allocation stacks: who made each big region
#   scripts/memory-report.sh --track 10:30    also sample the footprint 10 times, 30 s apart (leak check)
#   scripts/memory-report.sh --compare build/memory/memory-<time>.txt
#                                             what grew since that report
#   scripts/memory-report.sh --spike 40:120   wait (up to 120 s) for the footprint to rise 40 MB,
#                                             then report at once — for memory that's only there
#                                             while something is open (a popover)
#
# Finding what an action costs: `--stacks` (leaves the app running with stack
# logging), do the action in the app, then run the script again with
# `--compare` on the first report — later runs see the logging and add stacks.
#
# Options:
#   -l, --launch         quit any running DayEdge and launch the app fresh
#   -s, --stacks         launch with MallocStackLogging (implies --launch); the app
#                        stays running with it — any run on it prints allocation
#                        stacks of the large non-malloc regions (quit with make run)
#   -c, --compare FILE   the change since an earlier report: footprint, heap total,
#                        and the 20 malloc types that grew most
#   --spike MB:SECS      wait until the footprint is MB above where it was (checking
#                        every 0.3 s, giving up after SECS), then report
#   -w, --wait SECS      settle time after launching (default 20)
#   -t, --track N:SECS   sample the footprint N times every SECS seconds after the report
#   -m, --min MB         list regions at least this big (default 1)
#   -a, --app PATH       the app to launch (default build/DayEdge.app; make build makes it)
#   -p, --pid PID        measure this process instead of the running DayEdge
#   -o, --out DIR        where reports go (default build/memory)
#   -h, --help
#
# The report (also saved to build/memory/memory-<time>.txt):
#   1. Process         pid, version, uptime, how it was launched
#   2. Summary         footprint now and at peak, malloc heap total
#   3. By category     footprint's categories: dirty, clean, reclaimable, swapped
#   4. Large regions   every VM region >= --min MB: type, size, resident, dirty, swapped
#   5. Heap by type    the 25 malloc types holding the most bytes
#   6. Stacks          (--stacks) the allocating stack of each large non-malloc
#                      region, DayEdge's own frames marked with ▶
#   7. Tracking        (--track) footprint over time and the change from the first sample
#   8. Compared        (--compare) what grew since the earlier report
#
# Reading it: "footprint" is what Activity Monitor shows. Swapped/compressed
# memory still counts. A region that keeps growing across --track samples is
# a leak; one that settles is a cache. Needs Xcode's or the Command Line
# Tools' footprint, vmmap, heap and malloc_history (all in /usr/bin).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DayEdge.app"
OUT="$ROOT/build/memory"
LAUNCH=0
STACKS=0
WAIT=20
TRACK=""
MIN_MB=1
PID=""
COMPARE=""
SPIKE=""

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -l|--launch) LAUNCH=1 ;;
        -s|--stacks) STACKS=1; LAUNCH=1 ;;
        -w|--wait) WAIT="$2"; shift ;;
        -t|--track) TRACK="$2"; shift ;;
        -m|--min) MIN_MB="$2"; shift ;;
        -a|--app) APP="$2"; shift ;;
        -p|--pid) PID="$2"; shift ;;
        -o|--out) OUT="$2"; shift ;;
        -c|--compare) COMPARE="$2"; shift ;;
        --spike) SPIKE="$2"; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
    shift
done

# MARK: - The process

if [ "$LAUNCH" = 1 ]; then
    [ -d "$APP" ] || { echo "No app at $APP — run make build first." >&2; exit 1; }
    pkill -x DayEdge 2>/dev/null || true
    while pgrep -x DayEdge >/dev/null; do sleep 0.2; done
    if [ "$STACKS" = 1 ]; then
        # Launched directly (not with open) so the environment reaches it.
        MallocStackLogging=1 nohup "$APP/Contents/MacOS/DayEdge" >/dev/null 2>&1 &
    else
        open "$APP"
    fi
    for _ in $(seq 1 100); do PID="$(pgrep -x DayEdge | head -1 || true)"; [ -n "$PID" ] && break; sleep 0.1; done
    [ -n "$PID" ] || { echo "DayEdge didn't start." >&2; exit 1; }
    echo "Launched DayEdge (pid $PID)$([ "$STACKS" = 1 ] && echo ' with stack logging'); settling ${WAIT}s…" >&2
    sleep "$WAIT"
fi

if [ -z "$PID" ]; then
    PID="$(pgrep -x DayEdge | head -1 || true)"
    [ -n "$PID" ] || { echo "DayEdge isn't running — start it, or use --launch." >&2; exit 1; }
fi
kill -0 "$PID" 2>/dev/null || { echo "No process $PID." >&2; exit 1; }

# Footprint in MB, from footprint's summary line.
footprint_mb() {
    footprint "$1" 2>/dev/null | grep -m1 'Footprint:' | sed -E 's/.*Footprint: ([0-9.]+) ([KMG]?B).*/\1 \2/' |
        awk '{ n = $1; if ($2 == "KB") n /= 1024; if ($2 == "GB") n *= 1024; printf "%.0f", n }'
}

if [ -n "$SPIKE" ]; then
    RISE="${SPIKE%%:*}"; LIMIT="${SPIKE##*:}"
    start="$(footprint_mb "$PID")"
    echo "Footprint ${start} MB — waiting up to ${LIMIT}s for +${RISE} MB (do the action now)…" >&2
    deadline=$(( $(date +%s) + LIMIT ))
    while :; do
        now_mb="$(footprint_mb "$PID")"
        [ -n "$now_mb" ] && [ "$now_mb" -ge $(( start + RISE )) ] && { echo "Caught ${now_mb} MB — reporting." >&2; break; }
        [ "$(date +%s)" -ge "$deadline" ] && { echo "No rise of ${RISE} MB within ${LIMIT}s (now ${now_mb} MB); reporting anyway." >&2; break; }
        sleep 0.3
    done
fi

mkdir -p "$OUT"
REPORT="$OUT/memory-$(date +%Y%m%d-%H%M%S).txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

footprint --swapped "$PID" > "$TMP/footprint" 2>/dev/null || true
vmmap "$PID" > "$TMP/vmmap" 2>/dev/null || true
heap "$PID" -sortBySize > "$TMP/heap" 2>/dev/null || true
# Kept beside the report, whole, for --compare.
cp "$TMP/heap" "${REPORT%.txt}.heap"
# Stack logging is on when heap can name non-objects by their backtraces.
grep -q 'could be derived from allocation backtraces' "$TMP/heap" && LOGGING=0 || LOGGING=1
[ -n "$COMPARE" ] && [ ! -f "${COMPARE%.txt}.heap" ] && { echo "No ${COMPARE%.txt}.heap beside $COMPARE." >&2; exit 1; }

section() { printf '\n%s\n%s\n' "$1" "$(printf '%*s' "${#1}" '' | tr ' ' '─')"; }

{
    echo "DayEdge memory report — $(date '+%Y-%m-%d %H:%M:%S')"

    # MARK: 1. Process
    section "1. Process"
    COMMAND="$(ps -o command= -p "$PID" | cut -c1-120)"
    VERSION="$(grep -m1 '^Version:' "$TMP/heap" | sed 's/Version: *//' || true)"
    printf '%-14s %s\n' "PID" "$PID"
    printf '%-14s %s\n' "Version" "${VERSION:-?}"
    printf '%-14s %s\n' "Running for" "$(ps -o etime= -p "$PID" | tr -d ' ')"
    printf '%-14s %s\n' "Binary" "$COMMAND"
    printf '%-14s %s\n' "Launched" "$([ "$LAUNCH" = 1 ] && echo "fresh by this script, measured after ${WAIT}s" || echo "already running")"
    printf '%-14s %s\n' "Stack logging" "$([ "$LOGGING" = 1 ] && echo on || echo off)"
    printf '%-14s %s\n' "Show in Dock" "$(defaults read com.dayedge.app com.dayedge.dock.showsIcon 2>/dev/null | sed 's/1/on/;s/0/off/' || echo off)"

    # MARK: 2. Summary
    section "2. Summary"
    grep -m1 'Footprint:' "$TMP/footprint" | sed 's/.*Footprint: */Footprint now     /;s/ (.*//'
    grep -m1 'Physical footprint (peak):' "$TMP/heap" | sed 's/Physical footprint (peak): */Footprint peak    /'
    if [ "$LOGGING" = 1 ]; then
        perf="$(awk '/^Performance tool data/ { m = $0; sub(/.*\[ */, "", m); split(m, f, " "); n = f[3] + 0; u = substr(f[3], length(f[3])); if (u == "K") n /= 1024; t += n } END { printf "%.0f", t }' "$TMP/vmmap")"
        echo "Stack logging     ${perf} MB of the footprint is the logging itself — compare footprints without --stacks"
    fi
    grep -m1 'All zones:.*bytes)' "$TMP/heap" | sed -E 's/All zones: ([0-9]+) nodes \(([0-9]+) bytes\)/\1 \2/' |
        awk '{ printf "Malloc heap       %.1f MB in %d allocations\n", $2 / 1048576, $1 }'

    # MARK: 3. By category
    section "3. Footprint by category"
    sed -n '/Dirty/,/^$/p' "$TMP/footprint" | sed '/^$/d' | head -32

    # MARK: 4. Large regions
    section "4. Regions of at least ${MIN_MB} MB (virtual size)"
    printf '%-34s %-29s %9s %9s %9s %9s\n' "TYPE" "ADDRESS" "SIZE" "RESIDENT" "DIRTY" "SWAPPED"
    awk -v min="$MIN_MB" '
        function mb(s,  n, u) { n = s + 0; u = substr(s, length(s)); if (u == "K") n /= 1024; else if (u == "G") n *= 1024; else if (u != "M") n /= 1048576; return n }
        /^==== Summary/ { exit }
        match($0, /[0-9a-f]+-[0-9a-f]+ +\[/) {
            name = substr($0, 1, RSTART - 1); sub(/ +$/, "", name)
            rest = substr($0, RSTART)
            split(rest, parts, /\[|\]/); split(parts[2], s, " ")
            addr = rest; sub(/ +\[.*/, "", addr)
            if (name !~ /^(__TEXT|__LINKEDIT|__OBJC_RO|__DATA_CONST|__AUTH_CONST|dyld private memory|shared memory|unused dyld)/ && mb(s[1]) >= min)
                printf "%-34s %-29s %8.1fM %8.1fM %8.1fM %8.1fM\n", substr(name, 1, 34), addr, mb(s[1]), mb(s[2]), mb(s[3]), mb(s[4])
        }' "$TMP/vmmap" > "$TMP/regions"
    # Most memory actually held (dirty + swapped) first.
    awk '{ d = $(NF-1) + $NF; print d "\t" $0 }' "$TMP/regions" | sort -rn | cut -f2- | head -40

    # MARK: 5. Heap by type
    section "5. Malloc heap — top 25 types by bytes"
    sed -n '/^ *COUNT/,$p' "$TMP/heap" | sed -n '1p;3,27p' | cut -c1-150

    # MARK: 6. Stacks
    if [ "$LOGGING" = 1 ]; then
        section "6. Who allocated the large non-malloc regions"
        awk '{ d = $(NF-1) + $NF; print d "\t" $0 }' "$TMP/regions" | sort -rn | cut -f2- |
            grep -Ev '^(MALLOC|Stack|STACK|IOKit|__|Performance tool data)' |
            awk -v min="$MIN_MB" '$(NF-1) + $NF >= min' | head -8 |
            while read -r line; do
                start="0x$(echo "$line" | grep -oE '[0-9a-f]+-[0-9a-f]+' | head -1 | cut -d- -f1)"
                echo
                echo "■ $line"
                malloc_history "$PID" "$start" 2>/dev/null | grep -m1 -E 'VM_ALLOC|ALLOC' | tr '|' '\n' |
                    sed 's/^ *//' | grep -vE '^(0x[0-9a-f]+ \((libsystem|libdyld|dyld)\)|VM_ALLOC|ALLOC)' |
                    awk '{ frame[NR] = $0; if ($0 ~ /com\.dayedge\.app/) mine[NR] = 1 }
                         END {
                             # DayEdge'"'"'s own frames, then the last ten (where it was allocated).
                             last = 0
                             for (i = 1; i <= NR; i++) {
                                 if (!(i in mine) && i <= NR - 10) continue
                                 if (last && i > last + 1) print "    …"
                                 print ((i in mine) ? "  ▶ " : "    ") frame[i]; last = i
                             }
                         }' | cut -c1-170 ||
                    echo "    (no stack recorded)"
            done
    fi

    # MARK: 7. Tracking
    if [ -n "$TRACK" ]; then
        COUNT="${TRACK%%:*}"; EVERY="${TRACK##*:}"
        section "7. Footprint over time ($COUNT samples, every ${EVERY}s)"
        printf '%-10s %12s %12s\n' "TIME" "FOOTPRINT" "CHANGE"
        first=""
        for i in $(seq 1 "$COUNT"); do
            mb="$(footprint "$PID" 2>/dev/null | grep -m1 'Footprint:' | sed -E 's/.*Footprint: ([0-9.]+ [KMG]?B).*/\1/' | awk '{ n = $1; if ($2 == "KB") n /= 1024; if ($2 == "GB") n *= 1024; printf "%.1f", n }')"
            [ -z "$first" ] && first="$mb"
            printf '%-10s %10s MB %+10.1f MB\n' "$(date +%H:%M:%S)" "$mb" "$(echo "$mb - $first" | bc)"
            [ "$i" -lt "$COUNT" ] && sleep "$EVERY"
        done
        echo "Growing every sample: a leak. Rising, then flat: a cache."
    fi

    # MARK: 8. Compared
    if [ -n "$COMPARE" ]; then
        section "8. Since ${COMPARE##*/}"
        then_fp="$(grep -m1 '^Footprint now' "$COMPARE" | awk '{ print $3 }')"
        now_fp="$(grep -m1 'Footprint:' "$TMP/footprint" | sed -E 's/.*Footprint: ([0-9.]+).*/\1/')"
        printf '%-16s %8s MB → %8s MB   %+8.1f MB\n' "Footprint" "$then_fp" "$now_fp" "$(echo "$now_fp - $then_fp" | bc)"
        heap_total() { grep -m1 'All zones:.*bytes)' "$1" | sed -E 's/.*\(([0-9]+) bytes\).*/\1/'; }
        a="$(heap_total "${COMPARE%.txt}.heap")"; b="$(heap_total "$TMP/heap")"
        printf '%-16s %8.1f MB → %8.1f MB   %+8.1f MB\n' "Malloc heap" "$(echo "$a / 1048576" | bc -l)" "$(echo "$b / 1048576" | bc -l)" "$(echo "($b - $a) / 1048576" | bc -l)"
        echo
        printf '%12s %10s   %s\n' "GREW BY" "COUNT +" "TYPE"
        # Types keyed by everything after COUNT BYTES AVG.
        rows() { sed -n '/^ *COUNT/,$p' "$1" | sed '1,2d' | awk 'NF >= 4 && $1 ~ /^[0-9]+$/ { c = $1; b = $2; $1 = $2 = $3 = ""; sub(/^ +/, ""); print b "\t" c "\t" $0 }'; }
        rows "${COMPARE%.txt}.heap" > "$TMP/before"
        rows "$TMP/heap" > "$TMP/after"
        # A name can head several rows: summed.
        awk -F'\t' 'NR == FNR { b[$3] += $1; c[$3] += $2; next }
                    { a[$3] += $1; n[$3] += $2 }
                    END { for (k in a) { d = a[k] - b[k]; if (d > 0) printf "%10.1f KB %+10d   %s\n", d / 1024, n[k] - c[k], substr(k, 1, 110) } }' \
            "$TMP/before" "$TMP/after" | sort -rn | head -20
    fi
} | tee "$REPORT"

echo >&2
echo "Saved to ${REPORT#$ROOT/}" >&2

if [ "$LOGGING" = 1 ]; then
    echo "DayEdge is running with stack logging (slower, ~64 MB heavier). Do the action, then:" >&2
    echo "  scripts/memory-report.sh --compare ${REPORT#$ROOT/}" >&2
    echo "Quit it with make run (relaunches normally) when done." >&2
fi
