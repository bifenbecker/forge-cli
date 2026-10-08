# shellcheck shell=sh

# REST repository object, and the GraphQL fields gh repo list prints, to one shape.
GH_REPO_DEF='
def blank_null: if . == "" then null else . end;
def gh_repo: {
    path: .full_name,
    name,
    description: (.description | blank_null),
    url: .html_url,
    ssh_url,
    http_url: .clone_url,
    default_branch,
    visibility: (.visibility // (if .private then "private" else "public" end)),
    archived
};
def gh_repo_gql: {
    path: .nameWithOwner,
    name,
    description: (.description | blank_null),
    url,
    ssh_url: .sshUrl,
    http_url: (.url + ".git"),
    default_branch: (.defaultBranchRef.name // null),
    visibility: (.visibility | lower_or_null),
    archived: .isArchived
};
'

github_repo_emit() {
    forge_emit_doc "$1" "$GH_REPO_DEF gh_repo"
}

github_repo_view() {
    if ! forge_json_mode; then
        set -- repo view "$FORGE_R"
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture gh "$@"
        return
    fi
    gh_repo_doc=$(forge_capture github_api "$FORGE_API") || return $?
    github_repo_emit "$gh_repo_doc"
}

github_repo_list() {
    # gh repo list takes no -R; GH_HOST picks the host.
    set -- env GH_HOST="$FORGE_HOST" gh repo list
    [ -z "$arg_owner" ] || set -- "$@" "$arg_owner"
    set -- "$@" --limit "$opt_limit"
    [ -z "$opt_visibility" ] || set -- "$@" --visibility "$opt_visibility"
    if ! forge_json_mode; then
        forge_capture "$@"
        return
    fi
    gh_repo_list=$(forge_capture "$@" \
        --json nameWithOwner,name,description,url,sshUrl,defaultBranchRef,visibility,isArchived) || return $?
    forge_emit_doc "$gh_repo_list" "$GH_REPO_DEF [.[] | gh_repo_gql]"
}

github_repo_clone() {
    forge_capture gh repo clone "$FORGE_R" "$1" >&2
}

# A new fork is filled asynchronously, so its first clone can fail for a few seconds.
github_repo_clone_retry() {
    gh_clone_try=1
    while [ "$gh_clone_try" -lt 6 ]; do
        gh repo clone "$1" "$2" >/dev/null 2>&1 && return 0
        rm -rf -- "$2"
        sleep 5
        gh_clone_try=$((gh_clone_try + 1))
    done
    forge_capture gh repo clone "$1" "$2" >&2
}

github_repo_fork() {
    # The REST call returns the fork, also when it already existed; gh repo fork reports neither.
    gh_fork_doc=$(forge_capture github_api "$FORGE_API/forks" -X POST) || return $?
    gh_fork_path=$(printf '%s\n' "$gh_fork_doc" | _jq -r '.full_name')
    if [ -n "$opt_clone" ]; then
        gh_fork_dir=${opt_dir:-${gh_fork_path##*/}}
        github_repo_clone_retry "$FORGE_HOST/$gh_fork_path" "$gh_fork_dir" || return $?
    fi
    if forge_json_mode; then
        github_repo_emit "$gh_fork_doc"
    else
        printf '%s\n' "$gh_fork_doc" | _jq -r '.html_url'
        [ -z "$opt_clone" ] || printf '%s\n' "$gh_fork_dir"
    fi
}

github_repo_create() {
    set -- env GH_HOST="$FORGE_HOST" gh repo create "$arg_name" "--$opt_visibility"
    [ -z "$opt_description" ] || set -- "$@" --description "$opt_description"
    gh_create_out=$(forge_capture "$@") || return $?
    gh_create_url=$(printf '%s\n' "$gh_create_out" | grep -Eo 'https?://[^[:space:]]+' | tail -n 1)
    [ -n "$gh_create_url" ] || forge_die "gh did not report the new repository: $gh_create_out"
    if ! forge_json_mode; then
        printf '%s\n' "$gh_create_url"
        return
    fi
    gh_create_doc=$(forge_capture github_api "repos/${gh_create_url#*://*/}") || return $?
    github_repo_emit "$gh_create_doc"
}

github_repo_delete() {
    forge_capture gh repo delete "$FORGE_R" --yes >/dev/null
}

github_repo_archive() {
    forge_capture gh repo archive "$FORGE_R" --yes >/dev/null || return $?
    if forge_json_mode; then
        github_repo_view
    else
        github_web_url
        echo
    fi
}
