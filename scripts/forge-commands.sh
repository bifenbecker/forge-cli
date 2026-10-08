#!/bin/sh
# Lists every forge command as "<function suffix> <command path>", one per line.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FORGE_HOME=$root
for lib in util json detect args help dispatch; do
    . "$root/lib/core/$lib.sh"
done
for file in "$root"/lib/cmd/*.sh; do
    . "$file"
done

grep -ho '^cmd_[a-z0-9_]*()' "$root"/lib/cmd/*.sh | sed 's/^cmd_//; s/()$//' | sort | while IFS= read -r node; do
    path=$("help_$node" | sed -n '/^NAME$/{n;s/^  forge \(.*\) - .*/\1/p;}')
    printf '%s %s\n' "$node" "$path"
done
