# shellcheck shell=sh

# GitLab stores colours as "#rrggbb"; forge speaks bare hex.
GL_LABEL_DEF='
def gl_label: {
    name,
    color: ((.color // "") | ltrimstr("#") | ascii_downcase | if . == "" then null else . end),
    description: (if (.description // "") == "" then null else .description end)
};
'

# GET a list endpoint with at most $2 items, following pages past 100.
gitlab_label_list() {
    # glab label list has no search, so both modes read the API.
    gl_label_q="$FORGE_API/labels?include_ancestor_groups=true"
    [ -z "$opt_search" ] || gl_label_q="$gl_label_q&search=$(forge_urlencode "$opt_search")"
    gl_label_list=$(gitlab_api_limit "$gl_label_q" "$opt_limit") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_label_list" "$GL_LABEL_DEF [.[] | gl_label]"
    else
        printf '%s\n' "$gl_label_list" |
            _jq -r "$GL_LABEL_DEF .[] | gl_label | [.name, .color, (.description // \"\")] | @tsv"
    fi
}

gitlab_label_create() {
    # The API requires a colour; this is the one glab and the web UI default to.
    set -- "$FORGE_API/labels" -X POST -f "name=$arg_name" -f "color=#${opt_color:-428bca}"
    [ -z "$opt_description" ] || set -- "$@" -f "description=$opt_description"
    gl_label_doc=$(forge_capture gitlab_api "$@") || return $?
    printf '%s\n' "$gl_label_doc" | _jq "$GL_LABEL_DEF gl_label"
}

gitlab_label_edit() {
    set -- "$FORGE_API/labels/$(forge_urlencode "$arg_name")" -X PUT
    [ -z "$opt_name" ] || set -- "$@" -f "new_name=$opt_name"
    [ -z "$opt_color" ] || set -- "$@" -f "color=#$opt_color"
    [ -z "$opt_description_set" ] || set -- "$@" -f "description=$opt_description"
    gl_label_doc=$(forge_capture gitlab_api "$@") || return $?
    printf '%s\n' "$gl_label_doc" | _jq "$GL_LABEL_DEF gl_label"
}

gitlab_label_delete() {
    forge_capture gitlab_api "$FORGE_API/labels/$(forge_urlencode "$arg_name")" -X DELETE >/dev/null
}
