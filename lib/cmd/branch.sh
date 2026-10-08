# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/branch.sh

BRANCH_JSON_SHAPE='{name, sha, protected, default, url}
  sha is the head commit; default is true for the repository default branch only.'

help_branch() {
    cat <<'EOF'
forge branch - branches on the remote and their protection

These commands act on the host through its API, not on local branches.

COMMANDS
  list        List branches
  view        Show one branch
  delete      Delete a branch on the remote
  protect     Protect a branch: no force push, no deletion, changes only through a request
  unprotect   Remove the protection of a branch

Run 'forge branch <command> --help' for details.
EOF
}

branch_require_name() {
    [ -n "$1" ] || forge_usage_die "<name> is required"
}

branch_parse_name() {
    arg_name=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    branch_require_name "$arg_name"
}

# After a change: the URL in text mode, the full branch in JSON mode.
branch_report() {
    if forge_json_mode; then
        forge_call branch_view "$1"
    else
        (FORGE_JSON=1 FORGE_JQ=.url && forge_call branch_view "$1")
    fi
}

help_branch_list() {
    cat <<EOF
NAME
  forge branch list - list branches on the remote

USAGE
  forge branch list [--limit <n>] [--search <text>]

DESCRIPTION
  Lists the branches of the remote repository in name order.

FLAGS
  -L, --limit <n>     At most this many branches (default 30)
  --search <text>     Only branches whose name contains this text (case-sensitive on GitHub)

OUTPUT
  Text: one branch name per line.
  JSON: array of $BRANCH_JSON_SHAPE

PLATFORM NOTES
  GitHub: has no server-side search, so --search reads every branch and filters them.
  GitLab: --search also takes ^text (starts with) and text\$ (ends with).

EXAMPLES
  forge branch list
  forge branch list --search release/ --json
  forge branch list --jq '.[] | select(.protected) | .name'
EOF
}

cmd_branch_list() {
    opt_limit=30 opt_search=''
    while [ $# -gt 0 ]; do
        case $1 in
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            --search) forge_arg "$@"; opt_search=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    forge_call branch_list
}

help_branch_view() {
    cat <<EOF
NAME
  forge branch view - show one branch on the remote

USAGE
  forge branch view <name>

DESCRIPTION
  Shows the head commit and protection of a branch. Exits 4 when the remote has no such
  branch.

ARGUMENTS
  <name>   Branch name, e.g. feature/login

OUTPUT
  Text: name, sha, protected, default and url as "key: value" lines.
  JSON: $BRANCH_JSON_SHAPE

EXAMPLES
  forge branch view main
  forge branch view feature/login --jq .sha
EOF
}

cmd_branch_view() {
    branch_parse_name "$@"
    if forge_json_mode; then
        forge_call branch_view "$arg_name"
        return
    fi
    branch_view_doc=$(FORGE_JSON=1 FORGE_JQ='' forge_call branch_view "$arg_name") || exit $?
    printf '%s\n' "$branch_view_doc" | _jq -r '"name: \(.name)", "sha: \(.sha)",
        "protected: \(.protected)", "default: \(.default)", "url: \(.url)"'
}

help_branch_delete() {
    cat <<'EOF'
NAME
  forge branch delete - delete a branch on the remote

USAGE
  forge branch delete <name>

DESCRIPTION
  Deletes the branch on the host without asking. The local branch is untouched. The host
  refuses the default branch and protected branches. Exits 4 when there is no such branch.

ARGUMENTS
  <name>   Branch name

OUTPUT
  Text: nothing.
  JSON: {"name": "feature/login", "deleted": true}

EXAMPLES
  forge branch delete feature/login
EOF
}

cmd_branch_delete() {
    branch_parse_name "$@"
    forge_call branch_delete "$arg_name"
    if forge_json_mode; then
        _jq -n --arg name "$arg_name" '{name: $name, deleted: true}' | forge_emit '.'
    fi
}

help_branch_protect() {
    cat <<'EOF'
NAME
  forge branch protect - protect a branch

USAGE
  forge branch protect <name>

DESCRIPTION
  Applies one fixed protection, the common baseline: nobody pushes to the branch directly,
  changes arrive through a merged request, force pushes and deletion are refused. Replaces
  any protection the branch already had, so finer rules set in the web UI are lost.
  Exits 4 when there is no such branch.

ARGUMENTS
  <name>   Branch name

OUTPUT
  Text: the URL of the branch.
  JSON: the branch, as forge branch view --json.

PLATFORM NOTES
  GitHub: a classic branch protection rule requiring a pull request with 0 approvals;
          administrators may bypass it. Private repositories need a paid plan.
  GitLab: a protected branch with push "No one", merge "Developers + Maintainers",
          force push off. An existing protection is changed in place; where the instance
          refuses that, it is removed and created anew, and if that creation fails the
          command warns that the branch is left unprotected and exits 1.

EXAMPLES
  forge branch protect release/1.x
EOF
}

cmd_branch_protect() {
    branch_parse_name "$@"
    forge_call branch_protect "$arg_name"
    branch_report "$arg_name"
}

help_branch_unprotect() {
    cat <<'EOF'
NAME
  forge branch unprotect - remove the protection of a branch

USAGE
  forge branch unprotect <name>

DESCRIPTION
  Removes the branch protection, so pushes and deletion are governed by repository
  permissions again. A branch that is not protected is left as it is (exit 0).
  Exits 4 when there is no such branch.

ARGUMENTS
  <name>   Branch name

OUTPUT
  Text: the URL of the branch.
  JSON: the branch, as forge branch view --json.

PLATFORM NOTES
  GitHub: removes the classic protection rule of this branch; rulesets still apply.
  GitLab: removes the protected-branch entry named exactly <name>; wildcard entries
          that match it still apply.

EXAMPLES
  forge branch unprotect release/1.x
EOF
}

cmd_branch_unprotect() {
    branch_parse_name "$@"
    forge_call branch_unprotect "$arg_name"
    branch_report "$arg_name"
}
