# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/issue.sh

ISSUE_JSON_SHAPE='{id, title, state, author, url, description, labels[], assignees[],
         milestone, created_at, updated_at, closed_at}
  state is open or closed. milestone is the milestone title, or null. description is null
  when empty.'

help_issue() {
    cat <<'EOF'
forge issue - issues of the repository

<id> is the issue number (GitHub) or the issue iid (GitLab): the number shown in the web UI.
On GitHub, issues and pull requests share one number sequence, and gh accepts a pull request
number where an issue is expected: check that url contains /issues/ when that matters.

COMMANDS
  list      List issues
  view      Show one issue
  create    Open an issue
  edit      Change title, description, labels, assignees, milestone
  close     Close an issue
  reopen    Reopen a closed issue
  delete    Delete an issue for good
  comment   Comments: list, add
  label     Labels of an issue: list, add, remove

Run 'forge issue <command> --help' for details.
EOF
}

issue_require_id() {
    [ -n "$1" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$1"
}

# After a change: the URL in text mode, the full issue in JSON mode.
issue_report() {
    if forge_json_mode; then
        forge_call issue_view "$1"
    else
        forge_call issue_url "$1"
    fi
}

# --- list --------------------------------------------------------------------------------

help_issue_list() {
    cat <<EOF
NAME
  forge issue list - list issues

USAGE
  forge issue list [--state <state>] [--limit <n>] [--author <user>] [--assignee <user>]
                   [--label <name>]... [--milestone <title>] [--search <text>]

DESCRIPTION
  Lists issues of the repository, newest first. Filters combine with AND; several --label
  flags mean the issue carries all of them. Pull and merge requests are never included.

FLAGS
  -s, --state <state>      open (default), closed or all
  -L, --limit <n>          At most this many issues (default 30)
  -A, --author <user>      Opened by this user; @me for yourself
  -a, --assignee <user>    Assigned to this user; @me for yourself
  -l, --label <name>       Carrying this label; repeat for several
  -m, --milestone <title>  In the milestone with this title
  -S, --search <text>      Free-text search in title and description

OUTPUT
  Text: the platform CLI's table. On GitLab with --limit above 100 (one glab page), forge's
        own: one issue per line, tab-separated: #id, title, labels.
  JSON: array of $ISSUE_JSON_SHAPE

PLATFORM NOTES
  GitHub: --search takes GitHub search syntax too (e.g. "no:assignee sort:updated-desc").
  GitLab: --search matches title and description only.

EXAMPLES
  forge issue list
  forge issue list --state closed --limit 5 --json
  forge issue list --assignee @me --label bug --jq '.[].id'
  forge issue list --milestone v1.2 --search "login timeout"
EOF
}

cmd_issue_list() {
    opt_state=open opt_limit=30 opt_author='' opt_assignee='' opt_labels='' opt_milestone='' opt_search=''
    while [ $# -gt 0 ]; do
        case $1 in
            -s | --state) forge_arg "$@"; opt_state=$2; shift 2 ;;
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -A | --author) forge_arg "$@"; opt_author=$2; shift 2 ;;
            -a | --assignee) forge_arg "$@"; opt_assignee=$2; shift 2 ;;
            -l | --label) forge_arg "$@"; opt_labels=$(forge_list_add "$opt_labels" "$2"); shift 2 ;;
            -m | --milestone) forge_arg "$@"; opt_milestone=$2; shift 2 ;;
            -S | --search) forge_arg "$@"; opt_search=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_one_of --state "$opt_state" open closed all
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    forge_call issue_list
}

# --- view --------------------------------------------------------------------------------

help_issue_view() {
    cat <<EOF
NAME
  forge issue view - show one issue

USAGE
  forge issue view <id> [--comments] [--web]

DESCRIPTION
  Shows title, state, people, labels, milestone and description of an issue.

ARGUMENTS
  <id>          Issue number

FLAGS
  -c, --comments  Text mode: include the comments
  -w, --web       Open the issue in the browser instead

OUTPUT
  Text: the platform CLI's view.
  JSON: $ISSUE_JSON_SHAPE

PLATFORM NOTES
  GitHub: a pull request number is accepted too and shows the pull request (url has /pull/).
  GitLab: a merge request iid is not an issue: exit 4 unless an issue has the same iid.

EXAMPLES
  forge issue view 7
  forge issue view 7 --comments
  forge issue view 7 --jq '{state, labels}'
EOF
}

cmd_issue_view() {
    arg_id='' opt_comments='' opt_web=''
    while [ $# -gt 0 ]; do
        case $1 in
            -c | --comments) opt_comments=1; shift ;;
            -w | --web) opt_web=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    forge_call issue_view "$arg_id"
}

# --- create ------------------------------------------------------------------------------

help_issue_create() {
    cat <<EOF
NAME
  forge issue create - open an issue

USAGE
  forge issue create --title <text> [--body <text> | --body-file <path|->]
                     [--assignee <user>]... [--label <name>]... [--milestone <title>]

DESCRIPTION
  Opens an issue. Nothing is prompted for: what is not given stays empty.

FLAGS
  -t, --title <text>         Title; required
  -b, --body <text>          Description (Markdown); default: empty
  -F, --body-file <path|->   Description from a file, or - for stdin
  -a, --assignee <user>      Assign; @me for yourself; repeatable
  -l, --label <name>         Add a label; repeatable. A label the repository lacks is created.
  -m, --milestone <title>    Put in the milestone with this title; it must exist

OUTPUT
  Text: the URL of the new issue.
  JSON: the new issue, as forge issue view --json:
        $ISSUE_JSON_SHAPE

EXAMPLES
  forge issue create --title "Login times out" --body "Steps: ..." --label bug
  forge issue create --title "Write docs" --assignee @me --milestone v1.2 --jq .id
  forge issue create --title "Crash on start" --body-file .tmp/report.md
EOF
}

cmd_issue_create() {
    opt_title='' opt_assignees='' opt_labels='' opt_milestone=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -a | --assignee) forge_arg "$@"; opt_assignees=$(forge_list_add "$opt_assignees" "$2"); shift 2 ;;
            -l | --label) forge_arg "$@"; opt_labels=$(forge_list_add "$opt_labels" "$2"); shift 2 ;;
            -m | --milestone) forge_arg "$@"; opt_milestone=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    [ -n "$opt_title" ] || forge_usage_die "--title is required"
    issue_create_id=$(forge_call issue_create) || exit $?
    issue_report "$issue_create_id"
}

# --- edit --------------------------------------------------------------------------------

help_issue_edit() {
    cat <<EOF
NAME
  forge issue edit - change an issue

USAGE
  forge issue edit <id> [--title <text>] [--body <text> | --body-file <path|->]
                   [--milestone <title> | --remove-milestone]
                   [--add-label <name>]... [--remove-label <name>]...
                   [--add-assignee <user>]... [--remove-assignee <user>]...

DESCRIPTION
  Changes only what is given; everything else stays. --body replaces the whole description.

ARGUMENTS
  <id>                       Issue number

FLAGS
  -t, --title <text>         New title
  -b, --body <text>          New description
  -F, --body-file <path|->   New description from a file, or - for stdin
  -m, --milestone <title>    Move to the milestone with this title
  --remove-milestone         Take the issue out of its milestone
  --add-label <name>         Add a label; repeatable. A label the repository lacks is created.
  --remove-label <name>      Remove a label; repeatable
  --add-assignee <user>      Add an assignee (@me for yourself); repeatable
  --remove-assignee <user>   Remove an assignee (@me for yourself); repeatable

OUTPUT
  Text: the URL of the issue.
  JSON: the issue after the change, as forge issue view --json:
        $ISSUE_JSON_SHAPE

EXAMPLES
  forge issue edit 7 --title "Login times out after 30s"
  forge issue edit 7 --add-label confirmed --remove-label needs-triage
  forge issue edit 7 --add-assignee @me --milestone v1.2 --json
  forge issue edit 7 --body-file - < body.md
EOF
}

cmd_issue_edit() {
    arg_id='' opt_title='' opt_milestone='' opt_remove_milestone='' opt_add_labels='' opt_remove_labels=''
    opt_add_assignees='' opt_remove_assignees=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -m | --milestone) forge_arg "$@"; opt_milestone=$2; shift 2 ;;
            --remove-milestone) opt_remove_milestone=1; shift ;;
            --add-label) forge_arg "$@"; opt_add_labels=$(forge_list_add "$opt_add_labels" "$2"); shift 2 ;;
            --remove-label) forge_arg "$@"; opt_remove_labels=$(forge_list_add "$opt_remove_labels" "$2"); shift 2 ;;
            --add-assignee) forge_arg "$@"; opt_add_assignees=$(forge_list_add "$opt_add_assignees" "$2"); shift 2 ;;
            --remove-assignee) forge_arg "$@"; opt_remove_assignees=$(forge_list_add "$opt_remove_assignees" "$2"); shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    [ -z "$opt_milestone" ] || [ -z "$opt_remove_milestone" ] ||
        forge_usage_die "--milestone and --remove-milestone exclude each other"
    forge_call issue_edit "$arg_id"
    issue_report "$arg_id"
}

# --- close / reopen / delete -------------------------------------------------------------

help_issue_close() {
    cat <<'EOF'
NAME
  forge issue close - close an issue

USAGE
  forge issue close <id> [--comment <text>] [--reason completed|not-planned]

DESCRIPTION
  Closes the issue. With --comment, leaves that comment as well. Closing a closed issue
  succeeds and changes nothing.

ARGUMENTS
  <id>               Issue number

FLAGS
  -c, --comment <text>   Comment to leave when closing
  -r, --reason <reason>  Why: completed (default) or not-planned

OUTPUT
  Text: the URL of the issue.
  JSON: the closed issue, as forge issue view --json.

PLATFORM NOTES
  GitHub: --reason sets the issue's close reason, shown in the web UI.
  GitLab: issues have no close reason; --reason not-planned prints a warning and the issue
          is closed like any other. Use --comment to record why.

EXAMPLES
  forge issue close 7
  forge issue close 7 --comment "Fixed in #12"
  forge issue close 9 --reason not-planned --comment "Out of scope"
EOF
}

cmd_issue_close() {
    arg_id='' opt_comment='' opt_reason=''
    while [ $# -gt 0 ]; do
        case $1 in
            -c | --comment) forge_arg "$@"; opt_comment=$2; shift 2 ;;
            -r | --reason) forge_arg "$@"; opt_reason=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    [ -z "$opt_reason" ] || forge_require_one_of --reason "$opt_reason" completed not-planned
    forge_call issue_close "$arg_id"
    issue_report "$arg_id"
}

help_issue_reopen() {
    cat <<'EOF'
NAME
  forge issue reopen - reopen a closed issue

USAGE
  forge issue reopen <id> [--comment <text>]

DESCRIPTION
  Reopens a closed issue. With --comment, leaves that comment as well.

ARGUMENTS
  <id>                   Issue number

FLAGS
  -c, --comment <text>   Comment to leave when reopening

OUTPUT
  Text: the URL of the issue.
  JSON: the reopened issue, as forge issue view --json.

EXAMPLES
  forge issue reopen 7
  forge issue reopen 7 --comment "Still happens on v1.3"
EOF
}

cmd_issue_reopen() {
    arg_id='' opt_comment=''
    while [ $# -gt 0 ]; do
        case $1 in
            -c | --comment) forge_arg "$@"; opt_comment=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    forge_call issue_reopen "$arg_id"
    issue_report "$arg_id"
}

help_issue_delete() {
    cat <<'EOF'
NAME
  forge issue delete - delete an issue for good

USAGE
  forge issue delete <id> --yes

DESCRIPTION
  Deletes the issue with its comments. This cannot be undone; to keep the history, use
  'forge issue close' instead. --yes is required as the confirmation.

ARGUMENTS
  <id>    Issue number

FLAGS
  -y, --yes  Confirm the deletion

OUTPUT
  Text: the id of the deleted issue.
  JSON: {id, deleted}   deleted is always true.

PLATFORM NOTES
  GitHub: needs admin rights on the repository.
  GitLab: needs the Owner role on the project, or administrator.

EXAMPLES
  forge issue delete 7 --yes
EOF
}

cmd_issue_delete() {
    arg_id='' opt_yes=''
    while [ $# -gt 0 ]; do
        case $1 in
            -y | --yes) opt_yes=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    [ -n "$opt_yes" ] || forge_usage_die "deleting an issue cannot be undone: pass --yes to confirm"
    forge_call issue_delete "$arg_id"
    if forge_json_mode; then
        forge_require jq
        _jq -n --argjson id "$arg_id" '{id: $id, deleted: true}' | forge_emit '.'
    else
        printf '%s\n' "$arg_id"
    fi
}

# --- comment -----------------------------------------------------------------------------

help_issue_comment() {
    cat <<'EOF'
forge issue comment - comments on an issue

COMMANDS
  list     Comments on an issue
  add      Comment on an issue

Run 'forge issue comment <command> --help' for details.
EOF
}

help_issue_comment_list() {
    cat <<'EOF'
NAME
  forge issue comment list - comments on an issue

USAGE
  forge issue comment list <id>

DESCRIPTION
  Lists the comments people wrote on the issue, oldest first, without system notes
  (label changes, state changes, cross-references).

ARGUMENTS
  <id>   Issue number

OUTPUT
  Text: one block per comment: id, author, date, body.
  JSON: array of {id, author, body, created_at, updated_at, url}
        An issue without comments gives [].

EXAMPLES
  forge issue comment list 7
  forge issue comment list 7 --jq '.[] | select(.author == "alice") | .body'
EOF
}

cmd_issue_comment_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    issue_comments_doc=$(FORGE_JQ='' forge_call issue_comment_list "$arg_id") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$issue_comments_doc" '.'
    else
        forge_emit_doc "$issue_comments_doc" \
            '.[] | "#\(.id)  \(.author)  \(.created_at)\n\(.body)\n"' -r
    fi
}

help_issue_comment_add() {
    cat <<'EOF'
NAME
  forge issue comment add - comment on an issue

USAGE
  forge issue comment add <id> (--body <text> | --body-file <path|->)

DESCRIPTION
  Adds a comment to the issue. Works on closed issues too.

ARGUMENTS
  <id>                       Issue number

FLAGS
  -b, --body <text>          Comment text (Markdown)
  -F, --body-file <path|->   Comment text from a file, or - for stdin

OUTPUT
  Text: the comment id.
  JSON: {id, author, body, created_at, updated_at, url}

EXAMPLES
  forge issue comment add 7 --body "Reproduced on main"
  forge issue comment add 7 --body-file .tmp/analysis.md --jq .url
EOF
}

cmd_issue_comment_add() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    forge_require_body "the comment"
    issue_comment_doc=$(FORGE_JQ='' forge_call issue_comment_add "$arg_id") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$issue_comment_doc" '.'
    else
        forge_emit_doc "$issue_comment_doc" '.id' -r
    fi
}

# --- label -------------------------------------------------------------------------------

help_issue_label() {
    cat <<'EOF'
forge issue label - labels of an issue

COMMANDS
  list     Labels on an issue
  add      Add labels
  remove   Remove labels

Run 'forge issue label <command> --help' for details.
EOF
}

help_issue_label_list() {
    cat <<'EOF'
NAME
  forge issue label list - labels on an issue

USAGE
  forge issue label list <id>

DESCRIPTION
  Prints the labels of the issue.

ARGUMENTS
  <id>   Issue number

OUTPUT
  Text: one label per line; nothing when the issue has none.
  JSON: array of label names.

EXAMPLES
  forge issue label list 7
  forge issue label list 7 --jq 'index("bug") != null'
EOF
}

cmd_issue_label_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    issue_require_id "$arg_id"
    issue_labels_print "$arg_id"
}

issue_labels_print() {
    issue_labels_user_jq=$FORGE_JQ
    issue_labels_doc=$(FORGE_JQ='' FORGE_JSON=1 forge_call issue_view "$1") || exit $?
    FORGE_JQ=$issue_labels_user_jq
    if forge_json_mode; then
        forge_emit_doc "$issue_labels_doc" '.labels'
    else
        forge_emit_doc "$issue_labels_doc" '.labels[]' -r
    fi
}

issue_label_args() {
    arg_id='' arg_values=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                else arg_values=$(forge_list_add "$arg_values" "$1")
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_values" ] || forge_usage_die "<id> and at least one label are required"
    forge_require_int "<id>" "$arg_id"
}

help_issue_label_add() {
    cat <<'EOF'
NAME
  forge issue label add - add labels to an issue

USAGE
  forge issue label add <id> <label>...

DESCRIPTION
  Adds the labels. A label that does not exist in the repository yet is created.
  A label the issue already carries is left as it is.

ARGUMENTS
  <id>      Issue number
  <label>   Label name; give several to add several

OUTPUT
  Text: the labels of the issue afterwards, one per line.
  JSON: array of label names.

EXAMPLES
  forge issue label add 7 bug confirmed
EOF
}

cmd_issue_label_add() {
    issue_label_args "$@"
    forge_call issue_label_add "$arg_id" "$arg_values"
    issue_labels_print "$arg_id"
}

help_issue_label_remove() {
    cat <<'EOF'
NAME
  forge issue label remove - remove labels from an issue

USAGE
  forge issue label remove <id> <label>...

DESCRIPTION
  Removes the labels. A label the issue does not carry is ignored.

ARGUMENTS
  <id>      Issue number
  <label>   Label name; give several to remove several

OUTPUT
  Text: the labels of the issue afterwards, one per line.
  JSON: array of label names.

EXAMPLES
  forge issue label remove 7 needs-triage
EOF
}

cmd_issue_label_remove() {
    issue_label_args "$@"
    forge_call issue_label_remove "$arg_id" "$arg_values"
    issue_labels_print "$arg_id"
}
