# shellcheck shell=sh

GH_LABEL_DEF='
def gh_label: {
    name,
    color: (.color | ascii_downcase),
    description: (if (.description // "") == "" then null else .description end)
};
'

github_label_list() {
    set -- label list -R "$FORGE_R" --limit "$opt_limit"
    [ -z "$opt_search" ] || set -- "$@" --search "$opt_search"
    if ! forge_json_mode; then
        forge_capture gh "$@"
        return
    fi
    gh_label_list=$(forge_capture gh "$@" --json name,color,description) || return $?
    forge_emit_doc "$gh_label_list" "$GH_LABEL_DEF [.[] | gh_label]"
}

# create and edit go through REST: it answers with the label, gh label create does not.
github_label_create() {
    set -- "$FORGE_API/labels" -X POST -f "name=$arg_name"
    [ -z "$opt_color" ] || set -- "$@" -f "color=$opt_color"
    [ -z "$opt_description" ] || set -- "$@" -f "description=$opt_description"
    gh_label_doc=$(forge_capture github_api "$@") || return $?
    printf '%s\n' "$gh_label_doc" | _jq "$GH_LABEL_DEF gh_label"
}

github_label_edit() {
    set -- "$FORGE_API/labels/$(forge_urlencode "$arg_name")" -X PATCH
    [ -z "$opt_name" ] || set -- "$@" -f "new_name=$opt_name"
    [ -z "$opt_color" ] || set -- "$@" -f "color=$opt_color"
    [ -z "$opt_description_set" ] || set -- "$@" -f "description=$opt_description"
    gh_label_doc=$(forge_capture github_api "$@") || return $?
    printf '%s\n' "$gh_label_doc" | _jq "$GH_LABEL_DEF gh_label"
}

github_label_delete() {
    forge_capture gh label delete "$arg_name" -R "$FORGE_R" --yes >/dev/null
}
