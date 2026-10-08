# shellcheck shell=sh

# The API addresses a milestone by its global id; forge, like the web UI, by its iid.
GL_MILESTONE_DEF='
def gl_milestone: {
    id: .iid,
    title,
    description: (if (.description // "") == "" then null else .description end),
    state: (if .state == "active" then "open" else .state end),
    due_date,
    url: .web_url
};
'

# The raw milestone given by iid or exact title. Exit 4 when there is none.
gitlab_milestone_raw() {
    case $1 in
        *[!0-9]*) gl_ms_q="$FORGE_API/milestones?title=$(forge_urlencode "$1")" ;;
        *) gl_ms_q="$FORGE_API/milestones?iids%5B%5D=$1" ;;
    esac
    gl_ms_found=$(forge_capture gitlab_api "$gl_ms_q") || return $?
    gl_ms_raw=$(printf '%s\n' "$gl_ms_found" | _jq '.[0] // empty')
    [ -n "$gl_ms_raw" ] || forge_not_found "no milestone '$1'"
    printf '%s\n' "$gl_ms_raw"
}

gitlab_milestone_global_id() {
    gl_ms_raw=$(gitlab_milestone_raw "$1") || return $?
    printf '%s\n' "$gl_ms_raw" | _jq -r '.id'
}

gitlab_milestone_shape() {
    printf '%s\n' "$1" | _jq "$GL_MILESTONE_DEF gl_milestone"
}

gitlab_milestone_list() {
    gl_ms_q="$FORGE_API/milestones?per_page=100"
    case $opt_state in
        open) gl_ms_q="$gl_ms_q&state=active" ;;
        closed) gl_ms_q="$gl_ms_q&state=closed" ;;
    esac
    # The milestones API takes no order_by or sort: all pages are read and sorted here.
    gl_ms_list=$(forge_capture gitlab_api_all "$gl_ms_q") || return $?
    printf '%s\n' "$gl_ms_list" | _jq --argjson n "$opt_limit" \
        "$GL_MILESTONE_DEF sort_by(.created_at) | reverse | .[:\$n] | [.[] | gl_milestone]"
}

gitlab_milestone_view() {
    gl_ms_doc=$(gitlab_milestone_raw "$1") || return $?
    gitlab_milestone_shape "$gl_ms_doc"
}

gitlab_milestone_create() {
    set -- "$FORGE_API/milestones" -X POST -f "title=$opt_title"
    [ -z "$opt_description" ] || set -- "$@" -f "description=$opt_description"
    [ -z "$opt_due_date" ] || set -- "$@" -f "due_date=$opt_due_date"
    gl_ms_doc=$(forge_capture gitlab_api "$@") || return $?
    gitlab_milestone_shape "$gl_ms_doc"
}

gitlab_milestone_edit() {
    gl_ms_id=$(gitlab_milestone_global_id "$1") || return $?
    set -- "$FORGE_API/milestones/$gl_ms_id" -X PUT
    [ -z "$opt_title" ] || set -- "$@" -f "title=$opt_title"
    [ -z "$opt_description_set" ] || set -- "$@" -f "description=$opt_description"
    [ -z "$opt_due_date_set" ] || set -- "$@" -f "due_date=$opt_due_date"
    gl_ms_doc=$(forge_capture gitlab_api "$@") || return $?
    gitlab_milestone_shape "$gl_ms_doc"
}

gitlab_milestone_state() {
    gl_ms_id=$(gitlab_milestone_global_id "$1") || return $?
    case $2 in
        closed) gl_ms_event=close ;;
        *) gl_ms_event=activate ;;
    esac
    gl_ms_doc=$(forge_capture gitlab_api "$FORGE_API/milestones/$gl_ms_id" -X PUT -f "state_event=$gl_ms_event") ||
        return $?
    gitlab_milestone_shape "$gl_ms_doc"
}

gitlab_milestone_delete() {
    gl_ms_raw=$(gitlab_milestone_raw "$1") || return $?
    gl_ms_id=$(printf '%s\n' "$gl_ms_raw" | _jq -r '.id')
    forge_capture gitlab_api "$FORGE_API/milestones/$gl_ms_id" -X DELETE >/dev/null || return $?
    printf '%s\n' "$gl_ms_raw" | _jq -r '.iid'
}
