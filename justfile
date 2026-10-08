# forge-cli tasks. `just` lists them; every recipe forwards its arguments to the script it runs.

set shell := ["sh", "-cu"]
set positional-arguments := true

# Show available recipes
help:
    @just --list --unsorted

# Lint every shell file and check that every command's help is complete
lint:
    shellcheck bin/forge install.sh lib/*/*.sh scripts/*.sh
    sh scripts/check-help.sh

# Run every static check, changing nothing
check:
    sh scripts/run-checks.sh static

# Gate the branch, review it, push it and open a draft request. Usage: just ship [BASE=<branch>] [DRY_RUN=1] [NO_REVIEW=1] [DRAFT=0]
ship *args:
    sh scripts/ship.sh "$@"

# Rebuild CHANGELOG.md from the commit history. Usage: just changelog [TAG=vX.Y.Z]
changelog *args:
    sh scripts/changelog.sh "$@"

# Prepare the next release, or publish the merged one; safe to rerun. Usage: just release [VERSION=vX.Y.Z]
release *args:
    sh scripts/release.sh "$@"

# Regenerate the command reference of the agent skill from the help texts
docs:
    sh scripts/gen-docs.sh

# Install the git hooks (prek)
hooks:
    prek install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push

# Create a worktree for a task. Usage: just worktree-create ISSUE=<n> [TYPE=feature] [TITLE="..."] [BASE=<branch>] | BRANCH=<branch>
worktree-create *args:
    sh scripts/worktree-create.sh "$@"

# Remove a worktree after its request merged. Usage: just worktree-cleanup [NAME=<dir>] [FORCE=1]
worktree-cleanup *args:
    sh scripts/worktree-cleanup.sh "$@"
