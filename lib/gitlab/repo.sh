# shellcheck shell=sh

GL_REPO_DEF='
def blank_null: if . == "" then null else . end;
def gl_repo: {
    path: .path_with_namespace,
    name: .path,
    description: (.description | blank_null),
    url: .web_url,
    ssh_url: .ssh_url_to_repo,
    http_url: .http_url_to_repo,
    default_branch: (.default_branch // null),
    visibility,
    archived: (.archived // false)
};
'

gitlab_repo_emit() {
    forge_emit_doc "$1" "$GL_REPO_DEF gl_repo"
}

# GET a list endpoint with at most $2 items, following pages past 100.
gitlab_repo_view() {
    if ! forge_json_mode; then
        # glab repo view takes the project as an argument, not -R.
        set -- repo view "$FORGE_R"
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture glab "$@"
        return
    fi
    gl_repo_doc=$(forge_capture gitlab_api "$FORGE_API") || return $?
    gitlab_repo_emit "$gl_repo_doc"
}

gitlab_repo_list() {
    # One owner name may be a group or a user; the API has a separate endpoint for each.
    if [ -z "$arg_owner" ]; then
        gl_repo_q='projects?owned=true'
    else
        gl_repo_owner=$(forge_urlencode "$arg_owner")
        if gitlab_api "groups/$gl_repo_owner" >/dev/null 2>&1; then
            gl_repo_q="groups/$gl_repo_owner/projects?include_subgroups=false"
        else
            gl_repo_q="users/$gl_repo_owner/projects?simple=false"
        fi
    fi
    gl_repo_q="$gl_repo_q&order_by=created_at&sort=desc"
    [ -z "$opt_visibility" ] || gl_repo_q="$gl_repo_q&visibility=$opt_visibility"
    gl_repo_list=$(gitlab_api_limit "$gl_repo_q" "$opt_limit") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_repo_list" "$GL_REPO_DEF [.[] | gl_repo]"
    else
        printf '%s\n' "$gl_repo_list" |
            _jq -r '.[] | [.path_with_namespace, .visibility, (.description // "")] | @tsv'
    fi
}

gitlab_repo_clone() {
    # With GITLAB_HOST and a path, glab clones over the protocol it is configured for.
    forge_capture env GITLAB_HOST="$FORGE_HOST" glab repo clone "$FORGE_REPO_PATH" "$1" >&2
}

# A new fork is filled asynchronously, so its first clone can fail for a few seconds.
gitlab_repo_clone_retry() {
    gl_clone_try=1
    while [ "$gl_clone_try" -lt 6 ]; do
        env GITLAB_HOST="$FORGE_HOST" glab repo clone "$1" "$2" >/dev/null 2>&1 && return 0
        rm -rf -- "$2"
        sleep 5
        gl_clone_try=$((gl_clone_try + 1))
    done
    forge_capture env GITLAB_HOST="$FORGE_HOST" glab repo clone "$1" "$2" >&2
}

gitlab_repo_fork() {
    gl_fork_doc=$(forge_capture gitlab_api "$FORGE_API/fork" -X POST) || return $?
    gl_fork_path=$(printf '%s\n' "$gl_fork_doc" | _jq -r '.path_with_namespace')
    if [ -n "$opt_clone" ]; then
        gl_fork_dir=${opt_dir:-${gl_fork_path##*/}}
        gitlab_repo_clone_retry "$gl_fork_path" "$gl_fork_dir" || return $?
    fi
    if forge_json_mode; then
        gitlab_repo_emit "$gl_fork_doc"
    else
        printf '%s\n' "$gl_fork_doc" | _jq -r '.web_url'
        [ -z "$opt_clone" ] || printf '%s\n' "$gl_fork_dir"
    fi
}

# The REST API, not glab repo create, which also runs git init or clones in the current directory.
gitlab_repo_create() {
    gl_create_name=${arg_name##*/}
    set -- projects -X POST -f "path=$gl_create_name" -f "name=$gl_create_name" \
        -f "visibility=$opt_visibility"
    [ -z "$opt_description" ] || set -- "$@" -f "description=$opt_description"
    case $arg_name in
        */*)
            gl_create_ns=$(forge_capture gitlab_api "namespaces/$(forge_urlencode "${arg_name%/*}")") || return $?
            set -- "$@" -F "namespace_id=$(printf '%s\n' "$gl_create_ns" | _jq -r '.id')"
            ;;
    esac
    gl_create_doc=$(forge_capture gitlab_api "$@") || return $?
    if forge_json_mode; then
        gitlab_repo_emit "$gl_create_doc"
    else
        printf '%s\n' "$gl_create_doc" | _jq -r '.web_url'
    fi
}

gitlab_repo_delete() {
    forge_capture gitlab_api "$FORGE_API" -X DELETE >/dev/null
}

# 'glab repo archive' downloads a tarball; archiving the project is a REST call.
gitlab_repo_archive() {
    gl_archive_doc=$(forge_capture gitlab_api "$FORGE_API/archive" -X POST) || return $?
    if forge_json_mode; then
        gitlab_repo_emit "$gl_archive_doc"
    else
        printf '%s\n' "$gl_archive_doc" | _jq -r '.web_url'
    fi
}
