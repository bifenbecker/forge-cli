# shellcheck shell=sh

gitlab_auth_status() {
    if ! forge_json_mode; then
        glab auth status --hostname "$FORGE_HOST" || return "$FORGE_EXIT_ERROR"
        return 0
    fi
    # The API is asked directly: it also covers a token given through GITLAB_TOKEN.
    gl_auth_err=$(forge_tmp)
    gl_auth_user=''
    if gl_auth_doc=$(gitlab_api user 2>"$gl_auth_err"); then
        gl_auth_user=$(printf '%s\n' "$gl_auth_doc" | _jq -r '.username // empty' 2>/dev/null) || gl_auth_user=''
    fi
    cat "$gl_auth_err" >&2
    # Only a 401 or glab's own "no token" says "not logged in"; anything else (network, 5xx) is
    # a failure about which no login state can be claimed.
    if [ -z "$gl_auth_user" ] && ! grep -qiE '401|unauthorized|no token|not logged in|auth login' "$gl_auth_err"; then
        rm -f "$gl_auth_err"
        forge_die "glab could not check the login for $FORGE_HOST"
    fi
    rm -f "$gl_auth_err"
    _jq -n --arg h "$FORGE_HOST" --arg u "$gl_auth_user" \
        '{platform: "gitlab", host: $h, authenticated: ($u != ""), user: (if $u == "" then null else $u end)}' |
        forge_emit '.'
    [ -n "$gl_auth_user" ] || return "$FORGE_EXIT_ERROR"
}
