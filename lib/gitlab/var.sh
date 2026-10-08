# shellcheck shell=sh
# Shared with lib/gitlab/secret.sh: on GitLab a secret is a masked variable.

GL_VAR_DEF='
def gl_scope: if . == "*" or . == null then null else . end;
def gl_var: {name: .key, value, scope: (.environment_scope | gl_scope)};
'

# Environment scope of a command: the --env value, or * (every environment).
gitlab_var_scope() {
    printf '%s' "${opt_env:-*}"
}

gitlab_var_path() {
    printf '%s/variables/%s?filter%%5Benvironment_scope%%5D=%s' \
        "$FORGE_API" "$1" "$(forge_urlencode "$(gitlab_var_scope)")"
}

# Every variable of the project, filtered to the --env scope when one is given.
gitlab_var_all() {
    gl_var_all=$(forge_capture gitlab_api_all "$FORGE_API/variables?per_page=100") || return $?
    printf '%s\n' "$gl_var_all" | _jq --arg env "${opt_env:-}" \
        '[.[] | select($env == "" or .environment_scope == $env)]'
}

# Sets gl_var_doc to the variable $1 in the current scope. Returns 4, quietly, when it is absent.
gitlab_var_fetch() {
    gl_vf_err=$(forge_tmp)
    gl_vf_rc=0
    gl_var_doc=$(forge_capture gitlab_api "$(gitlab_var_path "$1")" 2>"$gl_vf_err") || gl_vf_rc=$?
    [ "$gl_vf_rc" -eq 0 ] || [ "$gl_vf_rc" -eq "$FORGE_EXIT_NOT_FOUND" ] || cat "$gl_vf_err" >&2
    rm -f "$gl_vf_err"
    return "$gl_vf_rc"
}

# Like gitlab_var_fetch, but an absent variable ends the command with exit 4.
gitlab_var_need() {
    gitlab_var_fetch "$1" || {
        gl_vn_rc=$?
        [ "$gl_vn_rc" -ne "$FORGE_EXIT_NOT_FOUND" ] || forge_not_found "no variable $1 in scope $(gitlab_var_scope)"
        return "$gl_vn_rc"
    }
}

gitlab_var_masked() {
    [ "$(printf '%s\n' "$gl_var_doc" | _jq -r '.masked // false')" = true ]
}

# Usage: gitlab_var_write <name> <exists 0|1> [<extra jq object for a new variable>]
# The value travels to glab on stdin inside the JSON body, never as an argument.
gitlab_var_write() {
    if [ "$2" = 1 ]; then
        printf '%s' "$FORGE_BODY" |
            _jq -Rs --arg s "$(gitlab_var_scope)" '{value: ., filter: {environment_scope: $s}}' |
            forge_capture gitlab_api -X PUT "$FORGE_API/variables/$1" \
                -H 'Content-Type: application/json' --input -
    else
        gl_vw_extra=${3:-}
        [ -n "$gl_vw_extra" ] || gl_vw_extra='{}'
        printf '%s' "$FORGE_BODY" |
            _jq -Rs --arg k "$1" --arg s "$(gitlab_var_scope)" \
                "{key: \$k, value: ., environment_scope: \$s} + $gl_vw_extra" |
            forge_capture gitlab_api -X POST "$FORGE_API/variables" \
                -H 'Content-Type: application/json' --input -
    fi
}

gitlab_var_list() {
    gl_var_list=$(gitlab_var_all) || return $?
    gl_var_list=$(printf '%s\n' "$gl_var_list" | _jq '[.[] | select(.masked != true)]')
    if forge_json_mode; then
        forge_emit_doc "$gl_var_list" "$GL_VAR_DEF [.[] | gl_var]"
    else
        # glab variable list would also print masked values, so the table is built here.
        printf '%s\n' "$gl_var_list" | _jq -r '.[] | [.key, .value, .environment_scope] | @tsv'
    fi
}

gitlab_var_get() {
    gitlab_var_need "$1" || return $?
    ! gitlab_var_masked || forge_not_found "$1 is masked, so it is a secret; forge does not print secret values"
    if forge_json_mode; then
        forge_emit_doc "$gl_var_doc" "$GL_VAR_DEF gl_var"
    else
        printf '%s\n' "$gl_var_doc" | _jq -r '.value'
    fi
}

gitlab_var_set() {
    gl_vs_exists=1
    gitlab_var_fetch "$1" || {
        gl_vs_rc=$?
        [ "$gl_vs_rc" -eq "$FORGE_EXIT_NOT_FOUND" ] || return "$gl_vs_rc"
        gl_vs_exists=0
    }
    if [ "$gl_vs_exists" = 1 ] && gitlab_var_masked; then
        forge_die "$1 is masked, so it is a secret: use 'forge secret set $1'"
    fi
    gl_var_doc=$(gitlab_var_write "$1" "$gl_vs_exists") || return $?
    forge_json_mode || return 0
    forge_emit_doc "$gl_var_doc" "$GL_VAR_DEF gl_var"
}

gitlab_var_delete() {
    gitlab_var_need "$1" || return $?
    ! gitlab_var_masked || forge_not_found "$1 is masked, so it is a secret: use 'forge secret delete $1'"
    forge_capture gitlab_api -X DELETE "$(gitlab_var_path "$1")" >/dev/null
}
