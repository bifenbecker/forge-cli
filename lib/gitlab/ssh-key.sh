# shellcheck shell=sh

GL_SSH_KEY_DEF='def gl_ssh_key: {id, title, key, created_at};'

gitlab_ssh_key_list() {
    gl_sk_doc=$(forge_capture gitlab_api_all "user/keys?per_page=100") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_sk_doc" "$GL_SSH_KEY_DEF [.[] | gl_ssh_key]"
    else
        # glab prints no ids without --show-id and stops at one page of 30 keys.
        printf '%s\n' "$gl_sk_doc" | _jq -r '.[] | [.id, .title, .created_at] | @tsv'
    fi
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
