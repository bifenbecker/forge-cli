# shellcheck shell=sh

GL_BRANCH_DEF='
def gl_branch: {name, sha: .commit.id, protected, default, url: .web_url};
'

# GitLab access levels: 0 no one, 30 developers and maintainers, 40 maintainers.
GL_BRANCH_PUSH_LEVEL=0
GL_BRANCH_MERGE_LEVEL=30

gitlab_branch_path() {
    printf '%s/repository/branches/%s' "$FORGE_API" "$(forge_urlencode "$1")"
}

gitlab_protected_path() {
    printf '%s/protected_branches/%s' "$FORGE_API" "$(forge_urlencode "$1")"
}

gitlab_branch_list() {
    gl_branch_q="$FORGE_API/repository/branches?"
    [ -z "$opt_search" ] || gl_branch_q="${gl_branch_q}search=$(forge_urlencode "$opt_search")&"
    if [ "$opt_limit" -le 100 ]; then
        gl_branch_doc=$(forge_capture gitlab_api "${gl_branch_q}per_page=$opt_limit") || return $?
    else
        gl_branch_doc=$(forge_capture gitlab_api_all "${gl_branch_q}per_page=100") || return $?
        gl_branch_doc=$(printf '%s\n' "$gl_branch_doc" | _jq --argjson n "$opt_limit" '.[:$n]')
    fi
    if forge_json_mode; then
        forge_emit_doc "$gl_branch_doc" "$GL_BRANCH_DEF [.[] | gl_branch]"
    else
        printf '%s\n' "$gl_branch_doc" | _jq -r '.[].name'
    fi
}

gitlab_branch_view() {
    gl_branch_doc=$(forge_capture gitlab_api "$(gitlab_branch_path "$1")") || return $?
    forge_emit_doc "$gl_branch_doc" "$GL_BRANCH_DEF gl_branch"
}

gitlab_branch_delete() {
    forge_capture gitlab_api "$(gitlab_branch_path "$1")" -X DELETE >/dev/null
}

gitlab_branch_protect() {
    forge_capture gitlab_api "$(gitlab_branch_path "$1")" >/dev/null || return $?
    # An existing entry cannot be re-created (409) and PATCH cannot set merge access, so the
    # entry is replaced.
    gitlab_branch_unprotect "$1" || return $?
    forge_capture gitlab_api "$FORGE_API/protected_branches" -X POST -f "name=$1" \
        -F "push_access_level=$GL_BRANCH_PUSH_LEVEL" -F "merge_access_level=$GL_BRANCH_MERGE_LEVEL" \
        -F allow_force_push=false >/dev/null
}

gitlab_branch_unprotect() {
    forge_capture gitlab_api "$(gitlab_branch_path "$1")" >/dev/null || return $?
    gl_unprotect_status=0
    gl_unprotect_err=$(forge_tmp)
    gitlab_api "$(gitlab_protected_path "$1")" >/dev/null 2>"$gl_unprotect_err" || gl_unprotect_status=$?
    if [ "$gl_unprotect_status" -ne 0 ]; then
        # 404 here means the branch exists but is not protected: nothing to remove.
        if grep -q '404' "$gl_unprotect_err"; then
            rm -f "$gl_unprotect_err"
            return 0
        fi
        cat "$gl_unprotect_err" >&2
        rm -f "$gl_unprotect_err"
        return "$gl_unprotect_status"
    fi
    rm -f "$gl_unprotect_err"
    forge_capture gitlab_api "$(gitlab_protected_path "$1")" -X DELETE >/dev/null
}
