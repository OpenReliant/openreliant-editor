#!/usr/bin/env bash
# usage: check-files.sh [--staged]
#
# Fails when a file from the game, or one that looks like it, is in the repository or about to
# enter it: the files git tracks, or with --staged those the next commit holds, as the pre-commit
# hook checks them. A file fails when it has the extension of one of the game's file types, holds
# binary data but for the design's pictures and fonts, or is over 2 MiB. It also fails on a line of
# text with an em or en dash (U+2014, U+2013), which the project's text does without
# (CONTRIBUTING.md), in any text file but a licence.
set -euo pipefail
export LC_ALL=C

mode=${1:-}
case $mode in
    "" | --staged) ;;
    *) echo "usage: $0 [--staged]" >&2; exit 2 ;;
esac
cd "$(git rev-parse --show-toplevel)"

# The binary files the repository holds: the design's pictures, and Newtown, which the design pages
# show the editor's name in (design/fonts/README.md).
allowed_binary='^design/(images/[^/]+\.png|fonts/Newtown\.ttf)$'
game_types='hog|dte|shp|fm8|spr|fat|fnt|frc|tga|bik|icd|exe|dll|m3d|asi|cab|bin|dat|iso|cue|wav|mp3|ogg'
max_size=$((2 * 1024 * 1024))
licences='(^|/)LICENSE[^/]*$'
em_dash=$(printf '\342\200\224')
en_dash=$(printf '\342\200\223')

failed=0
fail() {
    printf '  %s: %s\n' "$1" "$2" >&2
    failed=1
}

paths() {
    case $mode in
        "") git ls-files ;;
        --staged) git diff --cached --name-only --diff-filter=ACMR ;;
    esac
}

while IFS= read -r path; do
    [ -f "$path" ] || continue
    lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$lower" | grep -Eq "\.($game_types)$"; then
        fail "$path" "has the extension of one of the game's files"
        continue
    fi
    size=$(wc -c < "$path")
    if [ "$size" -gt "$max_size" ]; then
        fail "$path" "is over 2 MiB"
        continue
    fi
    if grep -Iq . "$path" 2>/dev/null || [ ! -s "$path" ]; then
        # A text file: no dashes, but in a licence.
        if ! printf '%s' "$path" | grep -Eq "$licences"; then
            if grep -n -e "$em_dash" -e "$en_dash" "$path" >/dev/null; then
                fail "$path" "has an em or en dash on line $(grep -n -e "$em_dash" -e "$en_dash" "$path" | head -1 | cut -d: -f1)"
            fi
        fi
    elif ! printf '%s' "$path" | grep -Eq "$allowed_binary"; then
        fail "$path" "holds binary data"
    fi
done < <(paths)

if [ "$failed" -ne 0 ]; then
    echo "check-files: the files above can't be committed" >&2
    exit 1
fi
