#!/bin/sh
# Rebuilds CHANGELOG.md from the commit history: changelog.sh [TAG=vX.Y.Z]
set -eu

cd -- "$(dirname -- "$0")/.."

TAG=
for arg in "$@"; do
    case $arg in
        TAG=*) TAG=${arg#TAG=} ;;
        -h | --help | help) sed -n '2p' "$0" | sed 's/^# //'; exit 0 ;;
        *) echo "changelog.sh: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

command -v git-cliff >/dev/null 2>&1 || {
    echo "changelog.sh: git-cliff is required: https://git-cliff.org/docs/installation" >&2
    exit 1
}

if [ -n "$TAG" ]; then
    git-cliff --tag "$TAG" -o CHANGELOG.md
else
    git-cliff -o CHANGELOG.md
fi
