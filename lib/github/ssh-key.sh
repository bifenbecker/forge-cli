# shellcheck shell=sh

GH_SSH_KEY_DEF='def gh_ssh_key: {id, title, key, created_at};'

# GitHub answers 404 when the token lacks the key scopes. That is a failure, not "not found",
# so exit 4 is turned into 1 when gh names a missing scope.
github_ssh_key_run() {
    gh_skr_err=$(forge_tmp)
    gh_skr_rc=0
    forge_capture "$@" 2>"$gh_skr_err" || gh_skr_rc=$?
    cat "$gh_skr_err" >&2
    if [ "$gh_skr_rc" -eq "$FORGE_EXIT_NOT_FOUND" ] && grep -q 'scope' "$gh_skr_err"; then
        gh_skr_rc=$FORGE_EXIT_ERROR
    fi
    rm -f "$gh_skr_err"
    return "$gh_skr_rc"
}

github_ssh_key_list() {
    if ! forge_json_mode; then
        # gh ssh-key has no --hostname; GH_HOST picks the host.
        github_ssh_key_run env GH_HOST="$FORGE_HOST" gh ssh-key list
        return
    fi
    gh_sk_doc=$(github_ssh_key_run github_api "user/keys?per_page=100" --paginate --slurp) || return $?
    forge_emit_doc "$gh_sk_doc" "$GH_SSH_KEY_DEF [.[][] | gh_ssh_key]"
}

github_ssh_key_add() {
    gh_sk_doc=$(github_ssh_key_run github_api -X POST user/keys -f "title=$opt_title" \
        -f "key=$ssh_key_text") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_sk_doc" "$GH_SSH_KEY_DEF gh_ssh_key"
    else
        printf '%s\n' "$gh_sk_doc" | _jq -r '.id'
    fi
}

github_ssh_key_delete() {
    github_ssh_key_run github_api -X DELETE "user/keys/$1" >/dev/null
}
