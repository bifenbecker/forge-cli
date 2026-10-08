# shellcheck shell=sh

GL_ISSUE_DEF='
def blank_null: if . == "" then null else . end;
def gl_issue: {
    id: .iid,
    title,
    state: (if .state == "opened" then "open" else .state end),
    author: .author.username,
    url: .web_url,
    description: (.description | blank_null),
    labels: (.labels // []),
    assignees: [(.assignees // [])[].username],
    milestone: (.milestone.title // null),
    created_at,
    updated_at,
    closed_at
};
def gl_note($url): {id, author: .author.username, body, created_at, updated_at,
    url: ($url + "#note_" + (.id | tostring))};
'

gitlab_issue_url_of() {
    printf '%s/-/issues/%s' "$(gitlab_web_url)" "$1"
}

gitlab_issue_list() {
    gitlab_need_me "$opt_author $opt_assignee"
    # glab lists one page of at most 100; past that the text table is built from the API.
    if ! forge_json_mode && [ "$opt_limit" -le 100 ]; then
        set -- issue list -R "$FORGE_R" --per-page "$opt_limit"
        case $opt_state in
            closed) set -- "$@" --closed ;;
            all) set -- "$@" --all ;;
        esac
        [ -z "$opt_author" ] || set -- "$@" --author "$(gitlab_user "$opt_author")"
        [ -z "$opt_assignee" ] || set -- "$@" --assignee "$(gitlab_user "$opt_assignee")"
        [ -z "$opt_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_labels")"
        [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
        [ -z "$opt_search" ] || set -- "$@" --search "$opt_search"
        forge_capture glab "$@"
        return
    fi
    # No state parameter means all states.
    gl_q="$FORGE_API/issues?order_by=created_at&sort=desc"
    case $opt_state in
        open) gl_q="$gl_q&state=opened" ;;
        closed) gl_q="$gl_q&state=closed" ;;
    esac
    [ -z "$opt_author" ] || gl_q="$gl_q&author_username=$(forge_urlencode "$(gitlab_user "$opt_author")")"
    [ -z "$opt_assignee" ] || gl_q="$gl_q&assignee_username=$(forge_urlencode "$(gitlab_user "$opt_assignee")")"
    [ -z "$opt_labels" ] || gl_q="$gl_q&labels=$(forge_urlencode "$(forge_list_csv "$opt_labels")")"
    [ -z "$opt_milestone" ] || gl_q="$gl_q&milestone=$(forge_urlencode "$opt_milestone")"
    [ -z "$opt_search" ] || gl_q="$gl_q&search=$(forge_urlencode "$opt_search")"
    gl_list=$(gitlab_api_limit "$gl_q" "$opt_limit") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_list" "$GL_ISSUE_DEF [.[] | gl_issue]"
    else
        printf '%s\n' "$gl_list" | _jq -r \
            '.[] | ["#\(.iid)", .title, ((.labels // []) | join(", "))] | @tsv'
    fi
}

gitlab_issue_view() {
    if ! forge_json_mode; then
        set -- issue view "$1" -R "$FORGE_R"
        [ -z "${opt_comments:-}" ] || set -- "$@" --comments
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture glab "$@"
        return
    fi
    gl_issue=$(forge_capture gitlab_api "$FORGE_API/issues/$1") || return $?
    forge_emit_doc "$gl_issue" "$GL_ISSUE_DEF gl_issue"
}

gitlab_issue_url() {
    gl_issue=$(forge_capture gitlab_api "$FORGE_API/issues/$1") || return $?
    printf '%s\n' "$gl_issue" | _jq -r '.web_url'
}

gitlab_issue_create() {
    gitlab_need_me "$opt_assignees"
    # --yes skips the confirmation: forge runs unattended.
    set -- issue create -R "$FORGE_R" --yes --title "$opt_title" --description "${FORGE_BODY:-}"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_labels")"
    [ -z "$opt_assignees" ] || set -- "$@" --assignee "$(gitlab_users_csv "$opt_assignees")"
    gl_create_out=$(forge_capture glab "$@") || return $?
    # Newer GitLab versions link issues as work items.
    gl_create_url=$(printf '%s\n' "$gl_create_out" | grep -Eo 'https?://[^[:space:]]+/(issues|work_items)/[0-9]+' | tail -n 1)
    [ -n "$gl_create_url" ] || forge_die "glab did not report the new issue: $gl_create_out"
    printf '%s' "${gl_create_url##*/}"
}

# glab takes "+user" to add and "-user" to remove, comma-separated.
gitlab_issue_people_delta() {
    gl_delta=
    while IFS= read -r gl_item; do
        [ -z "$gl_item" ] || gl_delta=$(forge_list_add "$gl_delta" "+$(gitlab_user "$gl_item")")
    done <<EOF
$1
EOF
    while IFS= read -r gl_item; do
        [ -z "$gl_item" ] || gl_delta=$(forge_list_add "$gl_delta" "-$(gitlab_user "$gl_item")")
    done <<EOF
$2
EOF
    forge_list_csv "$gl_delta"
}

gitlab_issue_edit() {
    gitlab_need_me "$opt_add_assignees $opt_remove_assignees"
    gl_edit_id=$1
    # glab reads an empty value as "not given", so clearing goes through the API.
    if [ -n "$opt_remove_milestone" ]; then
        forge_capture gitlab_api "$FORGE_API/issues/$gl_edit_id" -X PUT -f milestone_id=0 >/dev/null || return $?
    fi
    if [ -n "${FORGE_BODY_SET:-}" ] && [ -z "$FORGE_BODY" ]; then
        forge_capture gitlab_api "$FORGE_API/issues/$gl_edit_id" -X PUT -f description= >/dev/null || return $?
    fi
    set -- issue update "$gl_edit_id" -R "$FORGE_R"
    gl_edit_base=$#
    [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
    [ -z "${FORGE_BODY:-}" ] || set -- "$@" --description "$FORGE_BODY"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_add_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_add_labels")"
    [ -z "$opt_remove_labels" ] || set -- "$@" --unlabel "$(forge_list_csv "$opt_remove_labels")"
    if [ -n "$opt_add_assignees$opt_remove_assignees" ]; then
        set -- "$@" --assignee "$(gitlab_issue_people_delta "$opt_add_assignees" "$opt_remove_assignees")"
    fi
    [ "$#" -gt "$gl_edit_base" ] || return 0
    forge_capture glab "$@" >/dev/null
}

gitlab_issue_note() {
    forge_capture gitlab_api "$FORGE_API/issues/$1/notes" -X POST -f "body=$2" >/dev/null
}

gitlab_issue_close() {
    [ "$opt_reason" != not-planned ] ||
        forge_warn "GitLab issues have no close reason; closing #$1 without one"
    if [ -n "$opt_comment" ]; then
        gitlab_issue_note "$1" "$opt_comment" || return $?
    fi
    forge_capture glab issue close "$1" -R "$FORGE_R" >/dev/null
}

gitlab_issue_reopen() {
    if [ -n "$opt_comment" ]; then
        gitlab_issue_note "$1" "$opt_comment" || return $?
    fi
    forge_capture glab issue reopen "$1" -R "$FORGE_R" >/dev/null
}

# Through the API: glab issue delete asks for confirmation.
gitlab_issue_delete() {
    forge_capture gitlab_api "$FORGE_API/issues/$1" -X DELETE >/dev/null
}

# --- comments ----------------------------------------------------------------------------

gitlab_issue_comment_list() {
    gl_notes=$(forge_capture gitlab_api_all "$FORGE_API/issues/$1/notes?sort=asc&order_by=created_at&per_page=100") ||
        return $?
    printf '%s\n' "$gl_notes" | _jq --arg url "$(gitlab_issue_url_of "$1")" \
        "$GL_ISSUE_DEF [.[] | select(.system | not) | gl_note(\$url)]"
}

gitlab_issue_comment_add() {
    gl_note=$(forge_capture gitlab_api "$FORGE_API/issues/$1/notes" -X POST -f "body=$FORGE_BODY") ||
        return $?
    printf '%s\n' "$gl_note" | _jq --arg url "$(gitlab_issue_url_of "$1")" "$GL_ISSUE_DEF gl_note(\$url)"
}

# --- labels ------------------------------------------------------------------------------

gitlab_issue_label_add() {
    forge_capture glab issue update "$1" -R "$FORGE_R" --label "$(forge_list_csv "$2")" >/dev/null
}

gitlab_issue_label_remove() {
    forge_capture glab issue update "$1" -R "$FORGE_R" --unlabel "$(forge_list_csv "$2")" >/dev/null
}
