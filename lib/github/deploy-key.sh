# shellcheck shell=sh

GH_DEPLOY_KEY_DEF='def gh_deploy_key: {id, title, key, read_only, created_at};'

github_deploy_key_list() {
    if ! forge_json_mode; then
        forge_capture gh repo deploy-key list -R "$FORGE_R"
        return
    fi
    # --slurp turns the pages into one array of arrays.
    gh_dk_doc=$(forge_capture github_api "$FORGE_API/keys?per_page=100" --paginate --slurp) || return $?
    forge_emit_doc "$gh_dk_doc" "$GH_DEPLOY_KEY_DEF [.[][] | gh_deploy_key]"
}

github_deploy_key_add() {
    if [ -n "$opt_write" ]; then gh_dk_ro=false; else gh_dk_ro=true; fi
    gh_dk_doc=$(forge_capture github_api -X POST "$FORGE_API/keys" -f "title=$opt_title" \
        -f "key=$deploy_key_text" -F "read_only=$gh_dk_ro") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_dk_doc" "$GH_DEPLOY_KEY_DEF gh_deploy_key"
    else
        printf '%s\n' "$gh_dk_doc" | _jq -r '.id'
    fi
}

github_deploy_key_delete() {
    forge_capture github_api -X DELETE "$FORGE_API/keys/$1" >/dev/null
}
