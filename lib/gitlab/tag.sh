# shellcheck shell=sh

GL_TAG_DEF='
def gl_tag($web): {
    name,
    sha: .commit.id,
    message: ((.message // "") | sub("\n+$"; "") | if . == "" then null else . end),
    url: ($web + "/-/tags/" + .name)
};
'

gitlab_tag_list() {
    if [ "$opt_limit" -le 100 ]; then
        gl_tag_doc=$(forge_capture gitlab_api "$FORGE_API/repository/tags?per_page=$opt_limit") || return $?
    else
        gl_tag_doc=$(forge_capture gitlab_api_all "$FORGE_API/repository/tags?per_page=100") || return $?
        gl_tag_doc=$(printf '%s\n' "$gl_tag_doc" | _jq --argjson n "$opt_limit" '.[:$n]')
    fi
    if forge_json_mode; then
        forge_emit_doc "$gl_tag_doc" "$GL_TAG_DEF [.[] | gl_tag(\$web)]" --arg web "$(gitlab_web_url)"
    else
        printf '%s\n' "$gl_tag_doc" | _jq -r '.[].name'
    fi
}

gitlab_tag_view() {
    gl_tag_doc=$(forge_capture gitlab_api "$FORGE_API/repository/tags/$(forge_urlencode "$1")") || return $?
    forge_emit_doc "$gl_tag_doc" "$GL_TAG_DEF gl_tag(\$web)" --arg web "$(gitlab_web_url)"
}

gitlab_tag_create() {
    gl_tag_ref=$opt_ref
    if [ -z "$gl_tag_ref" ]; then
        gl_tag_repo=$(forge_capture gitlab_api "$FORGE_API") || return $?
        gl_tag_ref=$(printf '%s\n' "$gl_tag_repo" | _jq -r '.default_branch')
    fi
    set -- "$FORGE_API/repository/tags" -X POST -f "tag_name=$1" -f "ref=$gl_tag_ref"
    # A message is what makes GitLab create an annotated tag.
    [ -z "$opt_message" ] || set -- "$@" -f "message=$opt_message"
    forge_capture gitlab_api "$@" >/dev/null
}

gitlab_tag_delete() {
    forge_capture gitlab_api "$FORGE_API/repository/tags/$(forge_urlencode "$1")" -X DELETE >/dev/null
}
