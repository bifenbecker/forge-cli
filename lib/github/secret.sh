# shellcheck shell=sh

GH_SECRET_DEF='def gh_secret: {name, updated_at: .updatedAt};'

github_secret_doc() {
    set -- secret list -R "$FORGE_R" --json name,updatedAt
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    forge_capture gh "$@"
}

github_secret_list() {
    if ! forge_json_mode; then
        set -- secret list -R "$FORGE_R"
        [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
        forge_capture gh "$@"
        return
    fi
    gh_secret_doc=$(github_secret_doc) || return $?
    forge_emit_doc "$gh_secret_doc" "$GH_SECRET_DEF [.[] | gh_secret]"
}

github_secret_set() {
    set -- secret set "$1" -R "$FORGE_R"
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    # Without --body gh reads the value from stdin, which keeps it off the process list.
    printf '%s' "$FORGE_BODY" | forge_capture gh "$@" >/dev/null || return $?
    forge_json_mode || return 0
    gh_secret_doc=$(github_secret_doc) || return $?
    # GitHub stores secret names upper-cased, whatever case they were set with.
    forge_emit_doc "$gh_secret_doc" \
        "$GH_SECRET_DEF .[] | select((.name | ascii_upcase) == (\$n | ascii_upcase)) | gh_secret" \
        --arg n "$arg_name"
}

github_secret_delete() {
    set -- secret delete "$1" -R "$FORGE_R"
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    forge_capture gh "$@" >/dev/null
}
