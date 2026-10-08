# shellcheck shell=sh

GL_DEPLOY_KEY_DEF='def gl_deploy_key: {id, title, key, read_only: ((.can_push // false) | not), created_at};'

gitlab_deploy_key_list() {
    if ! forge_json_mode; then
        forge_capture glab deploy-key list -R "$FORGE_R"
        return
    fi
    gl_dk_doc=$(forge_capture gitlab_api_all "$FORGE_API/deploy_keys?per_page=100") || return $?
    forge_emit_doc "$gl_dk_doc" "$GL_DEPLOY_KEY_DEF [.[] | gl_deploy_key]"
}

gitlab_deploy_key_add() {
    gl_dk_doc=$(forge_capture gitlab_api -X POST "$FORGE_API/deploy_keys" -f "title=$opt_title" \
        -f "key=$deploy_key_text" -F "can_push=$(gitlab_bool "$opt_write")") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_dk_doc" "$GL_DEPLOY_KEY_DEF gl_deploy_key"
    else
        printf '%s\n' "$gl_dk_doc" | _jq -r '.id'
    fi
}

gitlab_deploy_key_delete() {
    forge_capture gitlab_api -X DELETE "$FORGE_API/deploy_keys/$1" >/dev/null
}
