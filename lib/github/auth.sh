# shellcheck shell=sh

github_auth_status() {
    if ! forge_json_mode; then
        gh auth status --hostname "$FORGE_HOST" || return "$FORGE_EXIT_ERROR"
        return 0
    fi
    # With --json gh exits 0 whatever the state; the state is read from the document.
    gh_auth_doc=$(gh auth status --hostname "$FORGE_HOST" --json hosts 2>/dev/null) || gh_auth_doc='{}'
    gh_auth_user=$(printf '%s\n' "$gh_auth_doc" | _jq -r --arg h "$FORGE_HOST" \
        '[(.hosts[$h] // [])[] | select(.active and .state == "success") | .login][0] // empty')
    _jq -n --arg h "$FORGE_HOST" --arg u "$gh_auth_user" \
        '{platform: "github", host: $h, authenticated: ($u != ""), user: (if $u == "" then null else $u end)}' |
        forge_emit '.'
    [ -n "$gh_auth_user" ] || return "$FORGE_EXIT_ERROR"
}
