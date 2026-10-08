# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/milestone.sh

MILESTONE_JSON_SHAPE='{id, title, description, state, due_date, url}
  id is the milestone number (GitHub) or iid (GitLab), as in the milestone URL. state is open
  or closed. due_date is YYYY-MM-DD or null; description may be null.'

help_milestone() {
    cat <<'EOF'
forge milestone - milestones of the repository

<milestone> is the milestone number (GitHub) or iid (GitLab), as shown in its URL, or its
exact title. A value of digits only is always taken as a number.

COMMANDS
  list     List milestones
  view     Show one milestone
  create   Create a milestone
  edit     Change title, description or due date
  close    Close a milestone
  reopen   Reopen a closed milestone
  delete   Delete a milestone

Run 'forge milestone <command> --help' for details.
EOF
}

milestone_require_date() {
    case $2 in
        '') ;;
        [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
        *) forge_usage_die "$1 must be YYYY-MM-DD, got '$2'" ;;
    esac
}

# One positional <milestone>, nothing else.
milestone_one_arg() {
    arg_milestone=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_milestone" ] || forge_unexpected "$1"; arg_milestone=$1; shift ;;
        esac
    done
    [ -n "$arg_milestone" ] || forge_usage_die "<milestone> is required"
}

# After a change: the URL in text mode, the milestone in JSON mode.
milestone_report() {
    if forge_json_mode; then
        forge_emit_doc "$1" '.'
    else
        printf '%s\n' "$1" | _jq -r '.url'
    fi
}

# --- list --------------------------------------------------------------------------------

help_milestone_list() {
    cat <<EOF
NAME
  forge milestone list - list milestones

USAGE
  forge milestone list [--state <state>] [--limit <n>]

DESCRIPTION
  Lists the repository's milestones.

FLAGS
  --state <state>   open (default), closed or all
  -L, --limit <n>   At most this many milestones (default 30)

OUTPUT
  Text: one line per milestone: id, state, due date (- when none), title, separated by tabs.
  JSON: array of $MILESTONE_JSON_SHAPE

PLATFORM NOTES
  GitHub: ordered by due date, earliest first; milestones without one come first.
  GitLab: newest first.
  GitLab: only the project's own milestones; group milestones are not listed.

EXAMPLES
  forge milestone list
  forge milestone list --state all --json
  forge milestone list --jq '.[] | select(.due_date != null) | .title'
EOF
}

cmd_milestone_list() {
    opt_state=open opt_limit=30
    while [ $# -gt 0 ]; do
        case $1 in
            --state) forge_arg "$@"; opt_state=$2; shift 2 ;;
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_one_of --state "$opt_state" open closed all
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    milestone_doc=$(forge_call milestone_list) || exit $?
    if forge_json_mode; then
        forge_emit_doc "$milestone_doc" '.'
    else
        printf '%s\n' "$milestone_doc" |
            _jq -r '.[] | [(.id | tostring), .state, (.due_date // "-"), .title] | @tsv'
    fi
}

# --- view --------------------------------------------------------------------------------

help_milestone_view() {
    cat <<EOF
NAME
  forge milestone view - show one milestone

USAGE
  forge milestone view <milestone>

DESCRIPTION
  Shows title, state, due date, URL and description of a milestone, open or closed.
  Exits 4 when there is no such milestone.

ARGUMENTS
  <milestone>   Milestone number (GitHub) or iid (GitLab), or its exact title

OUTPUT
  Text: lines "title: ...", "id: ...", "state: ...", "due: ..." (- when none) and
        "url: ...", then a blank line and the description, if there is one.
  JSON: $MILESTONE_JSON_SHAPE

EXAMPLES
  forge milestone view 3
  forge milestone view "v1.2" --jq .state
EOF
}

cmd_milestone_view() {
    milestone_one_arg "$@"
    milestone_doc=$(forge_call milestone_view "$arg_milestone") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$milestone_doc" '.'
    else
        printf '%s\n' "$milestone_doc" | _jq -r '"title: \(.title)\nid: \(.id)\nstate: \(.state)\n" +
            "due: \(.due_date // "-")\nurl: \(.url)" +
            (if .description == null then "" else "\n\n\(.description)" end)'
    fi
}

# --- create ------------------------------------------------------------------------------

help_milestone_create() {
    cat <<EOF
NAME
  forge milestone create - create a milestone

USAGE
  forge milestone create --title <text> [--description <text>] [--due-date <YYYY-MM-DD>]

DESCRIPTION
  Creates an open milestone. Titles are unique per repository: an existing title fails (exit 1).

FLAGS
  -t, --title <text>          Title; required
  -d, --description <text>    Description
  --due-date <YYYY-MM-DD>     Due date

OUTPUT
  Text: the URL of the new milestone.
  JSON: $MILESTONE_JSON_SHAPE

EXAMPLES
  forge milestone create --title v1.3 --due-date 2026-12-01
  forge milestone create --title "Sprint 42" --description "Login and signup" --jq .id
EOF
}

cmd_milestone_create() {
    opt_title='' opt_description='' opt_due_date=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -d | --description) forge_arg "$@"; opt_description=$2; shift 2 ;;
            --due-date) forge_arg "$@"; opt_due_date=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    [ -n "$opt_title" ] || forge_usage_die "--title is required"
    milestone_require_date --due-date "$opt_due_date"
    milestone_doc=$(forge_call milestone_create) || exit $?
    milestone_report "$milestone_doc"
}

# --- edit --------------------------------------------------------------------------------

help_milestone_edit() {
    cat <<EOF
NAME
  forge milestone edit - change a milestone

USAGE
  forge milestone edit <milestone> [--title <text>] [--description <text>]
                       [--due-date <YYYY-MM-DD>]

DESCRIPTION
  Changes only what is given; at least one flag is required. To close or reopen, use
  'forge milestone close' and 'forge milestone reopen'.

ARGUMENTS
  <milestone>                 Milestone number (GitHub) or iid (GitLab), or its exact title

FLAGS
  -t, --title <text>          New title
  -d, --description <text>    New description; "" clears it
  --due-date <YYYY-MM-DD>     New due date; "" removes it

OUTPUT
  Text: the URL of the milestone.
  JSON: the milestone after the change, $MILESTONE_JSON_SHAPE

EXAMPLES
  forge milestone edit 3 --due-date 2026-12-15
  forge milestone edit v1.3 --title v1.4 --json
EOF
}

cmd_milestone_edit() {
    arg_milestone='' opt_title='' opt_description='' opt_description_set='' opt_due_date=''
    opt_due_date_set=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -d | --description) forge_arg "$@"; opt_description=$2; opt_description_set=1; shift 2 ;;
            --due-date) forge_arg "$@"; opt_due_date=$2; opt_due_date_set=1; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_milestone" ] || forge_unexpected "$1"; arg_milestone=$1; shift ;;
        esac
    done
    [ -n "$arg_milestone" ] || forge_usage_die "<milestone> is required"
    [ -n "$opt_title$opt_description_set$opt_due_date_set" ] ||
        forge_usage_die "nothing to change: pass --title, --description or --due-date"
    milestone_require_date --due-date "$opt_due_date"
    milestone_doc=$(forge_call milestone_edit "$arg_milestone") || exit $?
    milestone_report "$milestone_doc"
}

# --- close / reopen / delete -------------------------------------------------------------

help_milestone_close() {
    cat <<EOF
NAME
  forge milestone close - close a milestone

USAGE
  forge milestone close <milestone>

DESCRIPTION
  Closes the milestone. Its issues and requests keep it. Closing a closed milestone is a no-op.

ARGUMENTS
  <milestone>   Milestone number (GitHub) or iid (GitLab), or its exact title

OUTPUT
  Text: the URL of the milestone.
  JSON: the milestone after the change, $MILESTONE_JSON_SHAPE

EXAMPLES
  forge milestone close v1.3
EOF
}

cmd_milestone_close() {
    milestone_one_arg "$@"
    milestone_doc=$(forge_call milestone_state "$arg_milestone" closed) || exit $?
    milestone_report "$milestone_doc"
}

help_milestone_reopen() {
    cat <<EOF
NAME
  forge milestone reopen - reopen a closed milestone

USAGE
  forge milestone reopen <milestone>

DESCRIPTION
  Reopens the milestone. Reopening an open milestone is a no-op.

ARGUMENTS
  <milestone>   Milestone number (GitHub) or iid (GitLab), or its exact title

OUTPUT
  Text: the URL of the milestone.
  JSON: the milestone after the change, $MILESTONE_JSON_SHAPE

EXAMPLES
  forge milestone reopen 3
EOF
}

cmd_milestone_reopen() {
    milestone_one_arg "$@"
    milestone_doc=$(forge_call milestone_state "$arg_milestone" open) || exit $?
    milestone_report "$milestone_doc"
}

help_milestone_delete() {
    cat <<'EOF'
NAME
  forge milestone delete - delete a milestone

USAGE
  forge milestone delete <milestone>

DESCRIPTION
  Deletes the milestone. Its issues and requests lose it; they are not deleted.
  Exits 4 when there is no such milestone.

ARGUMENTS
  <milestone>   Milestone number (GitHub) or iid (GitLab), or its exact title

OUTPUT
  Text: nothing.
  JSON: {"id": 3, "deleted": true}

EXAMPLES
  forge milestone delete 3
EOF
}

cmd_milestone_delete() {
    milestone_one_arg "$@"
    milestone_delete_id=$(forge_call milestone_delete "$arg_milestone") || exit $?
    if forge_json_mode; then
        _jq -n --argjson id "$milestone_delete_id" '{id: $id, deleted: true}' | forge_emit '.'
    fi
}
