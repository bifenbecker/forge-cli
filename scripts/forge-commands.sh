#!/bin/sh
# Lists every forge command as "<function suffix> <command path>", one per line.
# With --help-text, prints "@@ <suffix>" before each command's full help instead.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FORGE_HOME=$root
for lib in util json detect args help dispatch; do
    . "$root/lib/core/$lib.sh"
done
for file in "$root"/lib/cmd/*.sh; do
    . "$file"
done

# One process for all commands: spawning tools per command is slow on Windows.
dump() {
    # shellcheck disable=SC2013 # function names hold no spaces
    for node in $(grep -ho '^cmd_[a-z0-9_]*()' "$root"/lib/cmd/*.sh | sed 's/^cmd_//; s/()$//' | sort); do
        printf '@@ %s\n' "$node"
        "help_$node"
    done
}

if [ "${1:-}" = --help-text ]; then
    dump
else
    dump | awk '
        /^@@ / { node = $2; next }
        prev == "NAME" && /^  forge .* - / { sub(/^  forge /, ""); sub(/ - .*/, ""); print node " " $0 }
        { prev = $0 }
    '
fi
