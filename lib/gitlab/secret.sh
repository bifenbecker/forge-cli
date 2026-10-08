# shellcheck shell=sh
# GitLab has no separate secrets: a secret is a masked CI/CD variable.

. "$FORGE_HOME/lib/gitlab/var.sh"

gitlab_secret_list() {
    gl_secret_list=$(gitlab_var_all) || return $?
    gl_secret_list=$(printf '%s\n' "$gl_secret_list" | _jq '[.[] | select(.masked == true)]')
    if forge_json_mode; then
        # GitLab keeps no timestamps for variables.
        forge_emit_doc "$gl_secret_list" '[.[] | {name: .key, updated_at: null}]'
    else
        printf '%s\n' "$gl_secret_list" | _jq -r '.[].key'
    fi
}

gitlab_secret_set() {
    gl_ss_exists=1
    gitlab_var_fetch "$1" || {
        gl_ss_rc=$?
        [ "$gl_ss_rc" -eq "$FORGE_EXIT_NOT_FOUND" ] || return "$gl_ss_rc"
        gl_ss_exists=0
    }
    if [ "$gl_ss_exists" = 1 ] && ! gitlab_var_masked; then
        forge_die "$1 exists as a plain (unmasked) variable; remove it with 'forge var delete $1' first"
    fi
    # masked_and_hidden exists from GitLab 17.4; older versions ignore it and only mask.
    gitlab_var_write "$1" "$gl_ss_exists" '{masked: true, masked_and_hidden: true}' >/dev/null || return $?
    forge_json_mode || return 0
    _jq -n --arg n "$1" '{name: $n, updated_at: null}' | forge_emit '.'
}

gitlab_secret_delete() {
    gitlab_var_need "$1" || return $?
    gitlab_var_masked || forge_not_found "$1 is a plain variable, not a secret: use 'forge var delete $1'"
    forge_capture gitlab_api -X DELETE "$(gitlab_var_path "$1")" >/dev/null
}
