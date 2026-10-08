# shellcheck shell=sh

gitlab_user_me() {
    gl_user_doc=$(forge_capture gitlab_api user) || return $?
    if forge_json_mode; then
        # .email is the primary address, present only for the user's own record and admins.
        forge_emit_doc "$gl_user_doc" '{username, name,
            email: ([.email, .public_email] | map(select(. != null and . != "")) | .[0]),
            url: .web_url}'
    else
        printf '%s\n' "$gl_user_doc" | _jq -r '.username'
    fi
}
