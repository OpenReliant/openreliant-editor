#!/bin/bash
# Takes the picture of each page in screens/ again, into images/, at 1440 by 900, with headless
# Chrome or Chromium, on Windows (from Git Bash), macOS or Linux. CHROME names the browser's program
# where it isn't found by itself.
set -u
cd "$(dirname "$0")"

find_chrome() {
    if [ -n "${CHROME:-}" ]; then
        echo "$CHROME"
        return
    fi
    for path in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
        "/Applications/Chromium.app/Contents/MacOS/Chromium" \
        "/c/Program Files/Google/Chrome/Application/chrome.exe" \
        "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"; do
        if [ -x "$path" ]; then
            echo "$path"
            return
        fi
    done
    for name in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$name" >/dev/null 2>&1; then
            command -v "$name"
            return
        fi
    done
}

# A path as the browser takes it: on Windows, Git Bash's /c/... becomes C:/...
native() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

chrome="$(find_chrome)"
if [ -z "$chrome" ]; then
    echo "No Chrome or Chromium found: set CHROME to its program" >&2
    exit 1
fi
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT

for page in screens/*.html; do
    name=$(basename "$page" .html)
    out="images/$name.png"
    rm -f "$out"
    # The browser stays open after it writes the picture, so it's stopped once the file is there.
    # The pages load Newtown from fonts/, which a page opened from a file may only do with
    # --allow-file-access-from-files.
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
        --window-size=1440,900 --virtual-time-budget=5000 --allow-file-access-from-files \
        --user-data-dir="$(native "$profile")" \
        --screenshot="$(native "$PWD/$out")" "file:///$(native "$PWD/$page" | sed 's#^/##')" >/dev/null 2>&1 &
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
    if command -v pkill >/dev/null 2>&1; then
        pkill -f -- "--user-data-dir=$(native "$profile")" 2>/dev/null
    fi
    if [ -s "$out" ]; then echo "$name"; else echo "$name: no picture" >&2; fi
done
