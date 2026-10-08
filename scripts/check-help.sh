#!/bin/sh
# Fails when a command's help lacks a required section or a NAME line.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FORGE_HOME=$root
for lib in util json detect args help dispatch; do
    . "$root/lib/core/$lib.sh"
done
for file in "$root"/lib/cmd/*.sh; do
    . "$file"
done

status=0
commands=$(sh "$root/scripts/forge-commands.sh")
while IFS=' ' read -r node path; do
    [ -n "$node" ] || continue
    text=$("help_$node")
    if [ -z "$path" ]; then
        printf 'help_%s: NAME line is missing or not "  forge <path> - <summary>"\n' "$node" >&2
        status=1
    fi
    for section in $FORGE_HELP_SECTIONS; do
        printf '%s\n' "$text" | grep -qx "$section" || {
            printf 'forge %s: help has no %s section\n' "${path:-$node}" "$section" >&2
            status=1
        }
    done
done <<LIST
$commands
LIST

count=$(printf '%s\n' "$commands" | grep -c .)
[ "$status" -ne 0 ] || printf 'help ok: %s commands\n' "$count"
exit "$status"
