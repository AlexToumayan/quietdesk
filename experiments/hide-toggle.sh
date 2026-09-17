#!/bin/bash
# hide-toggle.sh - experiments E1 and E8 in docs/FEASIBILITY.md
#
# Question: does writing com.apple.WindowManager StandardHideDesktopIcons hide
# Finder's desktop items live (no Finder relaunch), and what changes in the
# window list while the key is set?
#
# Steps, in order:
#   1. capture the current value of the key ("absent" if it is not set) and
#      Finder's process id
#   2. list low-level windows with lowwin                    -> before.txt
#   3. write StandardHideDesktopIcons = true and wait 2 s    (desktop items disappear)
#   4. list low-level windows again                          -> during.txt
#   5. restore the captured value (or delete the key) and wait 2 s
#   6. list low-level windows a third time                   -> after.txt
#   7. print the diffs before/during and before/after, and Finder's pid before/after
#
# The restore runs from an EXIT trap, so it also happens after Ctrl-C, a signal
# or a failing command. The desktop items are hidden for about two seconds.
# Nothing else on the machine is changed.
#
# Needs lowwin next to this script (swiftc -O -o lowwin lowwin.swift). If it is
# missing, it is compiled into the work directory.
#
# Usage: ./hide-toggle.sh [work-directory]

set -u

DOMAIN=com.apple.WindowManager
KEY=StandardHideDesktopIcons
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/hide-toggle.XXXXXX")}"
mkdir -p "$WORK" || exit 1

LOWWIN="$HERE/lowwin"
if [ ! -x "$LOWWIN" ]; then
    echo "lowwin not found next to the script; compiling it into $WORK" >&2
    swiftc -O -o "$WORK/lowwin" "$HERE/lowwin.swift" || exit 1
    LOWWIN="$WORK/lowwin"
fi

# 1. capture the current state
if ORIG="$(defaults read "$DOMAIN" "$KEY" 2>/dev/null)"; then
    case "$ORIG" in
        1|true|TRUE|YES) ORIG=true ;;
        *)               ORIG=false ;;
    esac
else
    ORIG=absent
fi
FINDER_PID_BEFORE="$(pgrep -u "$(id -u)" -x Finder | head -n 1)"
echo "captured: $KEY = $ORIG; Finder pid = ${FINDER_PID_BEFORE:-not running}"

restored=0
restore() {
    [ "$restored" = 1 ] && return
    restored=1
    if [ "$ORIG" = absent ]; then
        defaults delete "$DOMAIN" "$KEY" 2>/dev/null
        echo "restored: $KEY deleted (it was absent before)"
    else
        defaults write "$DOMAIN" "$KEY" -bool "$ORIG"
        echo "restored: $KEY = $ORIG"
    fi
}
trap restore EXIT
trap 'exit 130' INT TERM HUP

# 2. before
"$LOWWIN" | sort > "$WORK/before.txt"

# 3. hide the desktop items
defaults write "$DOMAIN" "$KEY" -bool true
echo "written: $KEY = true; waiting 2 s"
sleep 2

# 4. during
"$LOWWIN" | sort > "$WORK/during.txt"

# 5. restore (the EXIT trap would do this too; doing it here lets us measure "after")
restore
sleep 2

# 6. after
"$LOWWIN" | sort > "$WORK/after.txt"
FINDER_PID_AFTER="$(pgrep -u "$(id -u)" -x Finder | head -n 1)"

# 7. report
echo
echo "== windows added (>) or removed (<) while the items were hidden (before -> during)"
diff "$WORK/before.txt" "$WORK/during.txt" || true
echo
echo "== before -> after (expected: identical)"
if diff "$WORK/before.txt" "$WORK/after.txt"; then echo "(identical)"; fi
echo
echo "Finder pid before=${FINDER_PID_BEFORE:-?} after=${FINDER_PID_AFTER:-?}"
echo "window lists kept in $WORK"
