#!/bin/sh
# Creates a git worktree for a task.
#
# Usage:
#   sh scripts/worktree-create.sh ISSUE=<n> [TITLE="<title>"] [TYPE=<type>] [BASE=<branch>]
#   sh scripts/worktree-create.sh BRANCH=<branch name> [BASE=<branch>]
#
#   ISSUE   the GitHub issue number; its title is read with forge unless TITLE is given
#   TITLE   the task's title, which makes the branch slug
#   TYPE    the branch type (default from git.default_type in workflow.toml)
#   BRANCH  the whole branch name; no issue is read
#   BASE    the base branch (default from git.default_branch)
#
# The branch name follows git.branch_template in workflow.toml.

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

config() {
    sh "$ROOT/scripts/workflow.sh" get "$@"
}

DEFAULT_BASE=$(config git.default_branch)
DEFAULT_TYPE=$(config git.default_type)
BRANCH_TEMPLATE=$(config git.branch_template)
WORKTREES_DIR=$(config worktree.dir)
LINKS=$(config worktree.link '')

# The worktree directory is named after the branch, and a full path on Windows runs into the
# 260-character limit, so the slug of a long title is cut.
MAX_SLUG_LEN=60

usage() {
    sed -n '/^# Usage:/,/^$/{ s/^# \{0,1\}//; p; }' "$0" >&2
}

fail() {
    echo "$1" >&2
    exit 1
}

is_windows() {
    case $(uname -s) in
        MINGW* | MSYS* | CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

# Git Bash silently copies instead of linking, so Windows' own links are used: a junction for a
# directory, a hard link for a file. Neither needs administrator rights.
link_into_worktree() {
    if ! is_windows; then
        ln -sfn "$1" "$2"
        return
    fi
    if [ -e "$2" ] || [ -L "$2" ]; then
        if [ -d "$2" ]; then
            cmd //c rmdir "$(cygpath -w "$2")" >/dev/null 2>&1 || rm -rf "$2"
        else
            rm -f "$2"
        fi
    fi
    link_kind=//H
    [ ! -d "$1" ] || link_kind=//J
    cmd //c mklink "$link_kind" "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# Cut at a word boundary, so the branch name does not end mid-word.
truncate_slug() {
    if [ "${#1}" -le "$MAX_SLUG_LEN" ]; then
        printf '%s' "$1"
        return
    fi
    truncate_cut=$(printf '%s' "$1" | cut -c1-"$MAX_SLUG_LEN")
    printf '%s' "${truncate_cut%-*}"
}

build_branch_name() {
    printf '%s' "$BRANCH_TEMPLATE" | sed "s/{type}/$1/; s/{ticket}/$2/; s/{slug}/$3/"
}

ISSUE=
TITLE=
TYPE=
BRANCH=
BASE=

for arg in "$@"; do
    case $arg in
        ISSUE=*) ISSUE=${arg#ISSUE=} ;;
        TITLE=*) TITLE=${arg#TITLE=} ;;
        TYPE=*) TYPE=${arg#TYPE=} ;;
        BRANCH=*) BRANCH=${arg#BRANCH=} ;;
        BASE=*) BASE=${arg#BASE=} ;;
        -h | --help | help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage
            exit 2
            ;;
    esac
done

BASE=${BASE:-$DEFAULT_BASE}
TYPE=${TYPE:-$DEFAULT_TYPE}

[ -n "$ISSUE" ] || [ -n "$BRANCH" ] || { usage; exit 2; }
[ -z "$ISSUE" ] || [ -z "$BRANCH" ] ||
    fail "ISSUE= and BRANCH= are exclusive: a branch name is either built from a task or given whole"
[ -z "$TITLE" ] || [ -n "$ISSUE" ] || fail "TITLE= only means something together with ISSUE="

# Paths are taken from the root of the main working tree, so this runs from anywhere in the project.
main_root=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
! command -v cygpath >/dev/null 2>&1 || main_root=$(cygpath -u "$main_root")
cd "$main_root"

# Linear history rests on pull.rebase. An existing value is the owner's choice and stays.
if [ -z "$(git config --local --get pull.rebase || true)" ]; then
    git config --local pull.rebase true
    echo "Turned on pull.rebase for this repository"
fi

issue_key=
if [ -n "$ISSUE" ]; then
    issue_key=${ISSUE#\#}
    case $issue_key in
        '' | *[!0-9]*) fail "Not an issue number: $ISSUE" ;;
    esac
    if [ -z "$TITLE" ]; then
        echo "Reading issue #$issue_key..."
        TITLE=$(sh "$ROOT/bin/forge" issue view "$issue_key" --jq .title) ||
            fail "Could not read issue #$issue_key; pass the title: TITLE=\"...\""
    fi
    [ -n "$TITLE" ] || fail "Issue #$issue_key has no title"
    slug=$(truncate_slug "$(slugify "$TITLE")")
    [ -n "$slug" ] || fail "No slug could be built from \"$TITLE\" — give the branch name with BRANCH="
    BRANCH=$(build_branch_name "$TYPE" "$issue_key" "$slug")
    echo "Task: #$issue_key — $TITLE"
fi

# Slashes in a branch name must not become nested directories.
worktree_name=$(printf '%s' "$BRANCH" | tr / -)
worktree_dir="$WORKTREES_DIR/$worktree_name"

if [ -e "$worktree_dir" ]; then
    echo "The directory already exists: $worktree_dir" >&2
    fail "Remove it: just worktree-cleanup NAME=$worktree_name"
fi

echo "Fetching origin..."
git fetch origin --prune

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # A leftover local branch behind origin would have its first push rejected, after work started.
    if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        unpulled=$(git rev-list --count "$BRANCH..origin/$BRANCH")
        unpushed=$(git rev-list --count "origin/$BRANCH..$BRANCH")
        if [ "$unpulled" != 0 ]; then
            echo "The local $BRANCH is $unpulled commit(s) behind origin/$BRANCH" >&2
            if [ "$unpushed" = 0 ]; then
                fail "Catch up: git branch -f $BRANCH origin/$BRANCH"
            fi
            echo "The histories have diverged — $unpushed local commit(s) are not on origin" >&2
            fail "Sort out by hand which of them are still wanted"
        fi
    fi
    start_point="the local $BRANCH"
    git worktree add "$worktree_dir" "$BRANCH"
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    start_point="origin/$BRANCH"
    git worktree add "$worktree_dir" -b "$BRANCH" "origin/$BRANCH"
else
    git show-ref --verify --quiet "refs/remotes/origin/$BASE" || fail "The base branch origin/$BASE does not exist"

    # A branch for this issue may exist already; a second one is started only on purpose.
    if [ -n "$issue_key" ]; then
        siblings=$(git for-each-ref --format='%(refname:strip=3)' "refs/remotes/origin/*/$issue_key-*")
        if [ -n "$siblings" ]; then
            echo "Note: origin already has branches for this issue:" >&2
            printf '%s\n' "$siblings" | sed 's/^/  /' >&2
            echo "Continue in one of them: BRANCH=<branch name>" >&2
        fi
    fi

    # --no-track: otherwise `git pull` would merge the base branch in. The upstream appears on
    # the first `git push -u origin HEAD`.
    start_point="origin/$BASE"
    git worktree add --no-track "$worktree_dir" -b "$BRANCH" "origin/$BASE"
fi

while IFS= read -r link; do
    [ -n "$link" ] || continue
    if [ -e "$link" ]; then
        link_into_worktree "$main_root/$link" "$main_root/$worktree_dir/$link"
        echo "Linked $link"
    fi
done <<EOF
$LINKS
EOF

echo ""
echo "=== The worktree is ready ==="
echo "  Branch:        $BRANCH"
echo "  Branched from: $start_point"
echo "  Directory:     $worktree_dir"
echo "  Author:        $(git config user.name) <$(git config user.email)>"
echo ""
echo "  cd $worktree_dir"
