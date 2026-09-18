#!/bin/bash
# Reproducible idle measurement: runs the release build in real mode for N seconds and samples
# CPU time and resident memory. Restores the desktop automatically when the run ends.
# Usage: scripts/measure-idle.sh [seconds]   (default 40)
set -euo pipefail
cd "$(dirname "$0")/.."
SECS="${1:-40}"
BIN=".build/release/QuietDesk"
test -x "$BIN" || swift build -c release >/dev/null
# A private settings suite: the run is always enabled with default options, whatever the
# person's own QuietDesk settings are (a disabled app would measure nothing).
"$BIN" --test-seconds "$SECS" --defaults-suite dev.quietdesk.measure >/dev/null 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
printf '%-6s %-6s %-9s %s\n' "t(s)" "cpu%" "rss(MB)" "cputime"
for ((t=5; t<SECS; t+=5)); do
  sleep 5
  ps -o %cpu=,rss=,cputime= -p "$PID" | awk -v t="$t" '{printf "%-6s %-6s %-9.1f %s\n", t, $1, $2/1024, $3}'
done
wait "$PID" || true
trap - EXIT
echo "desktop setting after run: $(defaults read com.apple.WindowManager StandardHideDesktopIcons 2>&1 | tail -1)"
