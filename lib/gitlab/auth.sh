# shellcheck shell=sh

gitlab_auth_status() {
    if ! forge_json_mode; then
        glab auth status --hostname "$FORGE_HOST" || return "$FORGE_EXIT_ERROR"
        return 0
    fi
    # The API is asked directly: it also covers a token given through GITLAB_TOKEN.
    gl_auth_doc=$(gitlab_api user 2>/dev/null) || gl_auth_doc='{}'
    gl_auth_user=$(printf '%s\n' "$gl_auth_doc" | _jq -r '.username // empty' 2>/dev/null) || gl_auth_user=''
    _jq -n --arg h "$FORGE_HOST" --arg u "$gl_auth_user" \
        '{platform: "gitlab", host: $h, authenticated: ($u != ""), user: (if $u == "" then null else $u end)}' |
        forge_emit '.'
    [ -n "$gl_auth_user" ] || return "$FORGE_EXIT_ERROR"
}
