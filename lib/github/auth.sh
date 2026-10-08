# shellcheck shell=sh

github_auth_status() {
    if ! forge_json_mode; then
        gh auth status --hostname "$FORGE_HOST" || return "$FORGE_EXIT_ERROR"
        return 0
    fi
    # With --json gh exits 0 whatever the state; the state is read from the document. Its stderr
    # stays visible: it is the only trace of a failure that left no document.
    gh_auth_doc=$(gh auth status --hostname "$FORGE_HOST" --json hosts) ||
        forge_die "gh auth status failed for $FORGE_HOST"
    # "none": no active account for the host, i.e. really not logged in. An active account whose
    # check did not succeed may be a network error (gh reports both as "error"), so no state is
    # claimed for it.
    gh_auth_state=$(printf '%s\n' "$gh_auth_doc" | _jq -r --arg h "$FORGE_HOST" '
        if (.hosts | type) != "object" then "unreadable"
        else [(.hosts[$h] // [])[] | select(.active)][0] as $a
            | if $a == null then "none"
              elif $a.state == "success" then "user \($a.login)"
              else "failed \($a.state)\(if $a.error then ": \($a.error)" else "" end)"
              end
        end' 2>/dev/null) || gh_auth_state=unreadable
    case $gh_auth_state in
        none) gh_auth_user='' ;;
        'user '*) gh_auth_user=${gh_auth_state#user } ;;
        unreadable) forge_die "gh auth status gave no readable answer for $FORGE_HOST" ;;
        *) forge_die "gh could not check the login for $FORGE_HOST (${gh_auth_state#failed })" ;;
    esac
    _jq -n --arg h "$FORGE_HOST" --arg u "$gh_auth_user" \
        '{platform: "github", host: $h, authenticated: ($u != ""), user: (if $u == "" then null else $u end)}' |
        forge_emit '.'
    [ -n "$gh_auth_user" ] || return "$FORGE_EXIT_ERROR"
}
