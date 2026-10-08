#!/bin/sh
# Fails when a command's help lacks a required section or a well-formed NAME line.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$root/lib/core/help.sh"

sh "$root/scripts/forge-commands.sh" --help-text | awk -v sections="$FORGE_HELP_SECTIONS" '
    function check() {
        if (node == "") return
        if (!named) { printf "help_%s: NAME line is missing or not \"  forge <path> - <summary>\"\n", node > "/dev/stderr"; bad = 1 }
        for (i = 1; i <= n; i++) if (!(want[i] in seen)) {
            printf "help_%s: no %s section\n", node, want[i] > "/dev/stderr"; bad = 1
        }
        count++
    }
    BEGIN { n = split(sections, want, " ") }
    /^@@ / { check(); node = $2; named = 0; delete seen; prev = ""; next }
    { seen[$0] = 1 }
    prev == "NAME" && /^  forge .* - / { named = 1 }
    { prev = $0 }
    END { check(); if (!bad) printf "help ok: %d commands\n", count; exit bad }
'
