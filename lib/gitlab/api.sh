# shellcheck shell=sh

gitlab_api_call() {
    gl_api_endpoint=$(api_replace "$arg_endpoint" '{repo}' "$FORGE_API")
    set -- glab api --hostname "$FORGE_HOST" "$gl_api_endpoint" "$@"
    if ! forge_json_mode; then
        forge_capture "$@"
        return
    fi
    gl_api_out=$(forge_capture "$@") || return $?
    forge_emit_doc "$gl_api_out" '.'
}
