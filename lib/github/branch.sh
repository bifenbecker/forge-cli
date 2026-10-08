# shellcheck shell=sh

GH_BRANCH_DEF='
def gh_branch($default; $web): {
    name,
    sha: .commit.sha,
    protected,
    default: (.name == $default),
    url: ($web + "/tree/" + (.name | @uri | gsub("%2F"; "/")))
};
'

github_branch_default() {
    gh_bd_repo=$(forge_capture github_api "$FORGE_API") || return $?
    printf '%s\n' "$gh_bd_repo" | _jq -r '.default_branch'
}

github_branch_list() {
    gh_branch_default=$(github_branch_default) || return $?
    # GitHub cannot search branches; a search reads them all and filters here.
    if [ "$opt_limit" -le 100 ] && [ -z "$opt_search" ]; then
        gh_branch_doc=$(forge_capture github_api "$FORGE_API/branches?per_page=$opt_limit") || return $?
    else
        gh_branch_doc=$(forge_capture github_api "$FORGE_API/branches?per_page=100" --paginate --slurp) ||
            return $?
        gh_branch_doc=$(printf '%s\n' "$gh_branch_doc" | _jq --arg s "$opt_search" --argjson n "$opt_limit" \
            '[.[][] | select(.name | contains($s))] | .[:$n]')
    fi
    if forge_json_mode; then
        forge_emit_doc "$gh_branch_doc" "$GH_BRANCH_DEF [.[] | gh_branch(\$default; \$web)]" \
            --arg default "$gh_branch_default" --arg web "$(github_web_url)"
    else
        printf '%s\n' "$gh_branch_doc" | _jq -r '.[].name'
    fi
}

github_branch_view() {
    gh_branch_path=$(github_ref_path "$1")
    gh_branch_doc=$(forge_capture github_api "$FORGE_API/branches/$gh_branch_path") || return $?
    gh_branch_default=$(github_branch_default) || return $?
    forge_emit_doc "$gh_branch_doc" "$GH_BRANCH_DEF gh_branch(\$default; \$web)" \
        --arg default "$gh_branch_default" --arg web "$(github_web_url)"
}

github_branch_delete() {
    forge_capture github_api "$FORGE_API/git/refs/heads/$(github_ref_path "$1")" -X DELETE >/dev/null
}

github_branch_protect() {
    # The four top-level keys are mandatory; null switches a rule off.
    printf '%s\n' '{
        "required_status_checks": null,
        "enforce_admins": false,
        "required_pull_request_reviews": {"required_approving_review_count": 0},
        "restrictions": null,
        "allow_force_pushes": false,
        "allow_deletions": false
    }' | forge_capture github_api "$FORGE_API/branches/$(github_ref_path "$1")/protection" -X PUT --input - >/dev/null
}

github_branch_unprotect() {
    gh_unprotect_path=$(github_ref_path "$1")
    # "Branch not protected" is a 404 too: tell it from a missing branch by asking first.
    forge_capture github_api "$FORGE_API/branches/$gh_unprotect_path" >/dev/null || return $?
    gh_unprotect_err=$(forge_tmp)
    gh_unprotect_status=0
    github_api "$FORGE_API/branches/$gh_unprotect_path/protection" -X DELETE >/dev/null 2>"$gh_unprotect_err" ||
        gh_unprotect_status=$?
    if [ "$gh_unprotect_status" -ne 0 ] && ! grep -qi 'not protected' "$gh_unprotect_err"; then
        cat "$gh_unprotect_err" >&2
        rm -f "$gh_unprotect_err"
        return "$gh_unprotect_status"
    fi
    rm -f "$gh_unprotect_err"
}
