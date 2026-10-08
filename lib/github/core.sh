# shellcheck shell=sh

github_init() {
    forge_require gh "GitHub CLI, https://cli.github.com"
    # -R value for gh subcommands, and the REST prefix of the repository.
    FORGE_R="$FORGE_HOST/$FORGE_REPO_PATH"
    FORGE_API="repos/$FORGE_REPO_PATH"
}

github_api() {
    gh api --hostname "$FORGE_HOST" "$@"
}

github_owner() {
    printf '%s' "${FORGE_REPO_PATH%%/*}"
}

github_name() {
    printf '%s' "${FORGE_REPO_PATH#*/}"
}

github_web_url() {
    printf 'https://%s/%s' "$FORGE_HOST" "$FORGE_REPO_PATH"
}
