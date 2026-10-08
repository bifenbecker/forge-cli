# shellcheck shell=sh

gitlab_init() {
    forge_require glab "GitLab CLI, https://gitlab.com/gitlab-org/cli"
    # A full URL carries the host, so self-hosted instances work without GITLAB_HOST.
    FORGE_R="https://$FORGE_HOST/$FORGE_REPO_PATH"
    FORGE_API="projects/$(forge_urlencode "$FORGE_REPO_PATH")"
}

gitlab_api() {
    glab api --hostname "$FORGE_HOST" "$@"
}

# --paginate prints one array per page; this joins them into one.
gitlab_api_all() {
    gitlab_api_all_out=$(gitlab_api "$@" --paginate) || return $?
    printf '%s\n' "$gitlab_api_all_out" | _jq -s '[.[][]]'
}

gitlab_web_url() {
    printf 'https://%s/%s' "$FORGE_HOST" "$FORGE_REPO_PATH"
}

# "@me" means the account glab is logged in as. Resolved once, in the calling shell, so that a
# failure stops the command; gitlab_user then only substitutes and cannot fail.
# Usage: gitlab_need_me "<every user value the command got>"
gitlab_need_me() {
    case $1 in
        *@me*) ;;
        *) return 0 ;;
    esac
    [ -z "${GL_ME:-}" ] || return 0
    gl_user_doc=$(forge_capture gitlab_api user) || exit $?
    GL_ME=$(printf '%s\n' "$gl_user_doc" | _jq -r '.username // empty')
    [ -n "$GL_ME" ] || forge_die "cannot tell who @me is: glab returned no username"
}

gitlab_user() {
    if [ "$1" = @me ]; then
        printf '%s' "${GL_ME:?gitlab_need_me was not called}"
    else
        printf '%s' "$1"
    fi
}

gitlab_bool() {
    if forge_is_true "$1"; then printf true; else printf false; fi
}

# Newline-separated users to "a,b", with @me substituted.
gitlab_users_csv() {
    gl_users=''
    while IFS= read -r gl_u; do
        [ -z "$gl_u" ] || gl_users=$(forge_list_add "$gl_users" "$(gitlab_user "$gl_u")")
    done <<EOF2
$1
EOF2
    forge_list_csv "$gl_users"
}

# GET a list endpoint ("path?query") with at most $2 items, following pages past 100.
gitlab_api_limit() {
    if [ "$2" -le 100 ]; then
        forge_capture gitlab_api "$1&per_page=$2"
    else
        gl_limit_doc=$(forge_capture gitlab_api_all "$1&per_page=100") || return $?
        printf '%s\n' "$gl_limit_doc" | _jq --argjson n "$2" '.[:$n]'
    fi
}
