# shellcheck shell=sh

GH_ISSUE_FIELDS=number,title,state,author,url,body,labels,assignees,milestone,createdAt,updatedAt,closedAt

GH_ISSUE_DEF='
def gh_issue: {
    id: .number,
    title,
    state: (.state | ascii_downcase),
    author: .author.login,
    url,
    description: .body,
    labels: [.labels[].name],
    assignees: [.assignees[].login],
    milestone: (.milestone.title // null),
    created_at: .createdAt,
    updated_at: .updatedAt,
    closed_at: .closedAt
};
def gh_comment: {id, author: .user.login, body, created_at, updated_at, url: .html_url};
'

github_issue_list() {
    set -- issue list -R "$FORGE_R" --limit "$opt_limit" --state "$opt_state"
    [ -z "$opt_author" ] || set -- "$@" --author "$opt_author"
    [ -z "$opt_assignee" ] || set -- "$@" --assignee "$opt_assignee"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_search" ] || set -- "$@" --search "$opt_search"
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || set -- "$@" --label "$gh_label"
    done <<EOF
$opt_labels
EOF
    if forge_json_mode; then
        gh_list_doc=$(forge_capture gh "$@" --json "$GH_ISSUE_FIELDS") || return $?
        forge_emit_doc "$gh_list_doc" "$GH_ISSUE_DEF [.[] | gh_issue]"
    else
        forge_capture gh "$@"
    fi
}

github_issue_view() {
    if ! forge_json_mode; then
        set -- issue view "$1" -R "$FORGE_R"
        [ -z "${opt_comments:-}" ] || set -- "$@" --comments
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture gh "$@"
        return
    fi
    gh_view_doc=$(forge_capture gh issue view "$1" -R "$FORGE_R" --json "$GH_ISSUE_FIELDS") || return $?
    forge_emit_doc "$gh_view_doc" "$GH_ISSUE_DEF gh_issue"
}

github_issue_url() {
    forge_capture gh issue view "$1" -R "$FORGE_R" --json url --jq .url
}

# GitHub does not create a missing label on the fly; GitLab does.
github_issue_ensure_labels() {
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || gh label create "$gh_label" -R "$FORGE_R" >/dev/null 2>&1 || true
    done <<EOF
$1
EOF
}

github_issue_create() {
    # An explicit --body, even empty, keeps gh from prompting for one.
    set -- issue create -R "$FORGE_R" --title "$opt_title" --body "${FORGE_BODY:-}"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    github_issue_ensure_labels "$opt_labels"
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --label "$gh_item"
    done <<EOF
$opt_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --assignee "$gh_item"
    done <<EOF
$opt_assignees
EOF
    gh_create_out=$(forge_capture gh "$@") || return $?
    gh_create_url=$(printf '%s\n' "$gh_create_out" | grep -Eo 'https?://[^[:space:]]+/issues/[0-9]+' | tail -n 1)
    [ -n "$gh_create_url" ] || forge_die "gh did not report the new issue: $gh_create_out"
    printf '%s' "${gh_create_url##*/}"
}

github_issue_edit() {
    set -- issue edit "$1" -R "$FORGE_R"
    gh_edit_base=$#
    [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --body "$FORGE_BODY"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_remove_milestone" ] || set -- "$@" --remove-milestone
    github_issue_ensure_labels "$opt_add_labels"
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --add-label "$gh_item"
    done <<EOF
$opt_add_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --remove-label "$gh_item"
    done <<EOF
$opt_remove_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --add-assignee "$gh_item"
    done <<EOF
$opt_add_assignees
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --remove-assignee "$gh_item"
    done <<EOF
$opt_remove_assignees
EOF
    [ "$#" -gt "$gh_edit_base" ] || return 0
    forge_capture gh "$@" >/dev/null
}

github_issue_close() {
    set -- issue close "$1" -R "$FORGE_R"
    [ -z "$opt_comment" ] || set -- "$@" --comment "$opt_comment"
    case $opt_reason in
        completed) set -- "$@" --reason completed ;;
        not-planned) set -- "$@" --reason "not planned" ;;
    esac
    # gh only warns on stderr about an issue that is already closed; that is not a failure.
    forge_capture gh "$@" >/dev/null
}

github_issue_reopen() {
    set -- issue reopen "$1" -R "$FORGE_R"
    [ -z "$opt_comment" ] || set -- "$@" --comment "$opt_comment"
    forge_capture gh "$@" >/dev/null
}

github_issue_delete() {
    forge_capture gh issue delete "$1" -R "$FORGE_R" --yes >/dev/null
}

# --- comments ----------------------------------------------------------------------------

github_issue_comment_list() {
    gh_comments=$(forge_capture github_api "$FORGE_API/issues/$1/comments?per_page=100" --paginate) ||
        return $?
    printf '%s\n' "$gh_comments" | _jq -s "$GH_ISSUE_DEF [.[][] | gh_comment]"
}

github_issue_comment_add() {
    gh_comment=$(forge_capture github_api "$FORGE_API/issues/$1/comments" -X POST -f "body=$FORGE_BODY") ||
        return $?
    printf '%s\n' "$gh_comment" | _jq "$GH_ISSUE_DEF gh_comment"
}

# --- labels ------------------------------------------------------------------------------

github_issue_label_add() {
    github_issue_ensure_labels "$2"
    forge_capture gh issue edit "$1" -R "$FORGE_R" --add-label "$(forge_list_csv "$2")" >/dev/null
}

# One call per label: gh fails the whole edit when one of them is not on the issue.
github_issue_label_remove() {
    gh_label_id=$1
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || gh issue edit "$gh_label_id" -R "$FORGE_R" --remove-label "$gh_label" >/dev/null 2>&1 || true
    done <<EOF
$2
EOF
}
