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

# "@me" means the account glab is logged in as.
gitlab_user() {
    if [ "$1" = @me ]; then
        gitlab_api user | _jq -r '.username'
    else
        printf '%s' "$1"
    fi
}

gitlab_bool() {
    if forge_is_true "$1"; then printf true; else printf false; fi
}
