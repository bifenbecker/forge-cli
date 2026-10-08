#!/bin/sh
# Runs the checks workflow.toml assigns to a stage: run-checks.sh static | pre_push
#
# Each name in [checks] is a just recipe, so a check is defined once, in the justfile, and this
# file only decides which of them a given gate owes.
set -u

cd -- "$(dirname -- "$0")/.." || exit 1

stage=${1:-}
[ -n "$stage" ] || {
    echo "usage: run-checks.sh <stage>   (a key under [checks] in workflow.toml)" >&2
    exit 2
}

checks=$(sh scripts/workflow.sh get "checks.$stage") || exit 1
if [ -z "$(printf '%s' "$checks" | tr -d '[:space:]')" ]; then
    echo "run-checks.sh: [checks].$stage is empty, nothing to run"
    exit 0
fi

failed=
while IFS= read -r check; do
    [ -n "$check" ] || continue
    echo "==> $check"
    just "$check" || failed="$failed $check"
done <<EOF2
$checks
EOF2

if [ -n "$failed" ]; then
    echo
    echo "Failed:$failed"
    exit 1
fi
