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
    # 4 means the branch is not protected yet; any other failure stops before anything changes.
    gl_protect_old_status=0
    gl_protect_old=$(forge_capture_optional gitlab_api "$(gitlab_protected_path "$1")") ||
        gl_protect_old_status=$?
    case $gl_protect_old_status in
        0) ;;
        "$FORGE_EXIT_NOT_FOUND") gl_protect_old= ;;
        *) return "$gl_protect_old_status" ;;
    esac
    # An existing entry cannot be re-created (409). It is changed in place where the instance
    # allows it, so the branch is never left open; replacing it is the fallback.
    if [ -n "$gl_protect_old" ] && gitlab_branch_protect_patch "$1" "$gl_protect_old"; then
        return 0
    fi
    gitlab_branch_unprotect "$1" || return $?
    gl_protect_status=0
    forge_capture gitlab_api "$FORGE_API/protected_branches" -X POST -f "name=$1" \
        -F "push_access_level=$GL_BRANCH_PUSH_LEVEL" -F "merge_access_level=$GL_BRANCH_MERGE_LEVEL" \
        -F allow_force_push=false >/dev/null || gl_protect_status=$?
    [ "$gl_protect_status" -eq 0 ] && return 0
    [ -n "$gl_protect_old" ] || return "$gl_protect_status"
    forge_warn "WARNING: branch $1 is now UNPROTECTED: its old protection was removed and the new one" \
        "could not be created. Protect it again in the web UI or rerun 'forge branch protect $1'."
    return "$FORGE_EXIT_ERROR"
}

# PATCH takes access levels as entries to add and ids to destroy; the wanted role levels are
# kept or added, every other entry is removed. Quiet: on failure the caller replaces the entry.
gitlab_branch_protect_patch() {
    gl_pp_body=$(printf '%s\n' "$2" | _jq --argjson push "$GL_BRANCH_PUSH_LEVEL" \
        --argjson merge "$GL_BRANCH_MERGE_LEVEL" '
        def role($want): .access_level == $want and .user_id == null and .group_id == null
            and .deploy_key_id == null;
        def levels($want):
            [.[] | select(role($want) | not) | {id, _destroy: true}]
            + (if any(.[]; role($want)) then [] else [{access_level: $want}] end);
        {
            allow_force_push: false,
            allowed_to_push: ((.push_access_levels // []) | levels($push)),
            allowed_to_merge: ((.merge_access_levels // []) | levels($merge))
        }') || return $?
    printf '%s\n' "$gl_pp_body" | gitlab_api "$(gitlab_protected_path "$1")" -X PATCH --input - \
        -H "Content-Type: application/json" >/dev/null 2>&1
}

gitlab_branch_unprotect() {
    forge_capture gitlab_api "$(gitlab_branch_path "$1")" >/dev/null || return $?
    gl_unprotect_status=0
    forge_capture_optional gitlab_api "$(gitlab_protected_path "$1")" >/dev/null || gl_unprotect_status=$?
    # Not found here means the branch exists but is not protected: nothing to remove.
    [ "$gl_unprotect_status" -ne "$FORGE_EXIT_NOT_FOUND" ] || return 0
    [ "$gl_unprotect_status" -eq 0 ] || return "$gl_unprotect_status"
    forge_capture gitlab_api "$(gitlab_protected_path "$1")" -X DELETE >/dev/null
}
