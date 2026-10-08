# shellcheck shell=sh

github_user_me() {
    gh_user_doc=$(forge_capture github_api user) || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_user_doc" '{username: .login, name, email, url: .html_url}'
    else
        printf '%s\n' "$gh_user_doc" | _jq -r '.login'
    fi
}
