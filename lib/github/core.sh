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

# A branch or tag name as REST path segments: "#", "?" and "%" would otherwise cut or alter the
# path, while "/" in a ref name has to stay a separator for GitHub to find it.
github_ref_path() {
    forge_urlencode "$1" | sed 's#%2F#/#g'
}

# Removes labels from an issue or pull request, one REST call each. A label that is not on it is
# a 404 too, so the number is checked first and only then a 404 means "nothing to remove".
# Usage: github_labels_remove <number> <newline-separated labels>
github_labels_remove() {
    forge_capture github_api "$FORGE_API/issues/$1" >/dev/null || return $?
    gh_lr_err=$(forge_tmp)
    while IFS= read -r gh_lr_label; do
        [ -n "$gh_lr_label" ] || continue
        gh_lr_status=0
        forge_capture github_api -X DELETE "$FORGE_API/issues/$1/labels/$(forge_urlencode "$gh_lr_label")" \
            >/dev/null 2>"$gh_lr_err" || gh_lr_status=$?
        case $gh_lr_status in
            0 | "$FORGE_EXIT_NOT_FOUND") ;;
            *)
                cat "$gh_lr_err" >&2
                rm -f "$gh_lr_err"
                return "$gh_lr_status"
                ;;
        esac
    done <<EOF
$2
EOF
    rm -f "$gh_lr_err"
}
