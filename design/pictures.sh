#!/bin/bash
# Takes the picture of each page in screens/ again, into images/, at 1440 by 900, with headless
# Chrome. CHROME names Chrome's program; by default, the one macOS installs.
set -u
cd "$(dirname "$0")"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
for page in screens/*.html; do
    name=$(basename "$page" .html)
    out="images/$name.png"
    rm -f "$out"
    # Chrome stays open after it writes the picture, so it's stopped once the file is there.
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
        --window-size=1440,900 --virtual-time-budget=5000 --user-data-dir="$profile" \
        --screenshot="$PWD/$out" "file://$PWD/$page" >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 60); do
        if [ -s "$out" ]; then
            sleep 1
            break
        fi
        sleep 0.5
    done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    pkill -f -- "--user-data-dir=$profile" 2>/dev/null
    if [ -s "$out" ]; then echo "$name"; else echo "$name: no picture" >&2; fi
done
