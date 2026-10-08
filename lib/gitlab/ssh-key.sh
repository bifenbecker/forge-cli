# shellcheck shell=sh

GL_SSH_KEY_DEF='def gl_ssh_key: {id, title, key, created_at};'

gitlab_ssh_key_list() {
    if ! forge_json_mode; then
        forge_capture glab ssh-key list -R "$FORGE_R"
        return
    fi
    gl_sk_doc=$(forge_capture gitlab_api_all "user/keys?per_page=100") || return $?
    forge_emit_doc "$gl_sk_doc" "$GL_SSH_KEY_DEF [.[] | gl_ssh_key]"
}

gitlab_ssh_key_add() {
    gl_sk_doc=$(forge_capture gitlab_api -X POST user/keys -f "title=$opt_title" \
        -f "key=$ssh_key_text") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_sk_doc" "$GL_SSH_KEY_DEF gl_ssh_key"
    else
        printf '%s\n' "$gl_sk_doc" | _jq -r '.id'
    fi
}

gitlab_ssh_key_delete() {
    forge_capture gitlab_api -X DELETE "user/keys/$1" >/dev/null
}
