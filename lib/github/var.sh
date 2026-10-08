# shellcheck shell=sh

GH_VAR_DEF='def gh_var($env): {name, value, scope: (if $env == "" then null else $env end)};'

github_var_list() {
    set -- variable list -R "$FORGE_R"
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    if ! forge_json_mode; then
        forge_capture gh "$@"
        return
    fi
    gh_var_doc=$(forge_capture gh "$@" --json name,value) || return $?
    forge_emit_doc "$gh_var_doc" "$GH_VAR_DEF [.[] | gh_var(\$env)]" --arg env "$opt_env"
}

github_var_doc() {
    set -- variable get "$1" -R "$FORGE_R" --json name,value
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    forge_capture gh "$@"
}

github_var_get() {
    gh_var_doc=$(github_var_doc "$1") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_var_doc" "$GH_VAR_DEF gh_var(\$env)" --arg env "$opt_env"
    else
        printf '%s\n' "$gh_var_doc" | _jq -r '.value'
    fi
}

github_var_set() {
    set -- variable set "$1" -R "$FORGE_R"
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    # Without --body gh reads the value from stdin, which keeps it off the process list.
    printf '%s' "$FORGE_BODY" | forge_capture gh "$@" >/dev/null || return $?
    forge_json_mode || return 0
    github_var_get "$arg_name"
}

github_var_delete() {
    set -- variable delete "$1" -R "$FORGE_R"
    [ -z "$opt_env" ] || set -- "$@" --env "$opt_env"
    forge_capture gh "$@" >/dev/null
}
