# shellcheck shell=sh

# gh has no milestone command; everything here is the REST API.
GH_MILESTONE_DEF='
def gh_milestone: {
    id: .number,
    title,
    description: (if (.description // "") == "" then null else .description end),
    state,
    due_date: (if .due_on == null then null else .due_on[0:10] end),
    url: .html_url
};
'

# Number of a milestone given by number or exact title. Exit 4 when there is none.
github_milestone_number() {
    case $1 in
        *[!0-9]*) ;;
        *)
            printf '%s' "$1"
            return 0
            ;;
    esac
    gh_ms_all=$(forge_capture github_api "$FORGE_API/milestones?state=all&per_page=100" --paginate) ||
        return $?
    gh_ms_number=$(printf '%s\n' "$gh_ms_all" |
        _jq -rs --arg t "$1" '[.[][] | select(.title == $t) | .number] | first // empty')
    [ -n "$gh_ms_number" ] || forge_not_found "no milestone titled '$1'"
    printf '%s' "$gh_ms_number"
}

github_milestone_shape() {
    printf '%s\n' "$1" | _jq "$GH_MILESTONE_DEF gh_milestone"
}

# GitHub keeps due_on as a date but takes a timestamp; noon UTC is that date in every zone.
github_milestone_due() {
    if [ -n "$1" ]; then
        printf '%sT12:00:00Z' "$1"
    else
        printf 'null'
    fi
}

github_milestone_list() {
    gh_ms_q="$FORGE_API/milestones?state=$opt_state&sort=due_on&direction=asc"
    if [ "$opt_limit" -le 100 ]; then
        gh_ms_list=$(forge_capture github_api "$gh_ms_q&per_page=$opt_limit") || return $?
    else
        gh_ms_list=$(forge_capture github_api "$gh_ms_q&per_page=100" --paginate) || return $?
    fi
    # --paginate prints one array per page.
    printf '%s\n' "$gh_ms_list" |
        _jq -s --argjson n "$opt_limit" "$GH_MILESTONE_DEF [.[][] | gh_milestone] | .[:\$n]"
}

github_milestone_view() {
    gh_ms_n=$(github_milestone_number "$1") || return $?
    gh_ms_doc=$(forge_capture github_api "$FORGE_API/milestones/$gh_ms_n") || return $?
    github_milestone_shape "$gh_ms_doc"
}

github_milestone_create() {
    set -- "$FORGE_API/milestones" -X POST -f "title=$opt_title"
    [ -z "$opt_description" ] || set -- "$@" -f "description=$opt_description"
    [ -z "$opt_due_date" ] || set -- "$@" -f "due_on=$(github_milestone_due "$opt_due_date")"
    gh_ms_doc=$(forge_capture github_api "$@") || return $?
    github_milestone_shape "$gh_ms_doc"
}

github_milestone_edit() {
    gh_ms_n=$(github_milestone_number "$1") || return $?
    set -- "$FORGE_API/milestones/$gh_ms_n" -X PATCH
    [ -z "$opt_title" ] || set -- "$@" -f "title=$opt_title"
    [ -z "$opt_description_set" ] || set -- "$@" -f "description=$opt_description"
    # -F turns the word null into JSON null, which removes the due date.
    [ -z "$opt_due_date_set" ] || set -- "$@" -F "due_on=$(github_milestone_due "$opt_due_date")"
    gh_ms_doc=$(forge_capture github_api "$@") || return $?
    github_milestone_shape "$gh_ms_doc"
}

github_milestone_state() {
    gh_ms_n=$(github_milestone_number "$1") || return $?
    gh_ms_doc=$(forge_capture github_api "$FORGE_API/milestones/$gh_ms_n" -X PATCH -f "state=$2") ||
        return $?
    github_milestone_shape "$gh_ms_doc"
}

github_milestone_delete() {
    gh_ms_n=$(github_milestone_number "$1") || return $?
    forge_capture github_api "$FORGE_API/milestones/$gh_ms_n" -X DELETE >/dev/null || return $?
    printf '%s\n' "$gh_ms_n"
}
