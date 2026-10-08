# shellcheck shell=sh

github_api_call() {
    gh_api_endpoint=$(api_replace "$arg_endpoint" 'repos/{owner}/{repo}' "$FORGE_API")
    gh_api_endpoint=$(api_replace "$gh_api_endpoint" '{repo}' "$FORGE_API")
    # GH_REPO points gh's own {owner} and {branch} placeholders at the --repo repository.
    set -- env GH_REPO="$FORGE_R" gh api --hostname "$FORGE_HOST" "$gh_api_endpoint" "$@"
    if ! forge_json_mode; then
        forge_capture "$@"
        return
    fi
    gh_api_out=$(forge_capture "$@") || return $?
    forge_emit_doc "$gh_api_out" '.'
}
