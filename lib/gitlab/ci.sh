# shellcheck shell=sh

# GitLab returns UTC times ("...T10:00:00.123Z"), so ISO strings compare correctly as text.
GL_CI_DEF='
def gl_ci_run: {
    id,
    name: (.name // null),
    status: (.status | normalise_status),
    ref,
    sha,
    event: .source,
    url: .web_url,
    created_at,
    updated_at
};
def gl_ci_job: {
    id,
    name,
    stage,
    status: (.status | normalise_status),
    allow_failure,
    url: .web_url,
    started_at,
    finished_at
};
def gl_ci_artifacts: (now | todate) as $now | [.[]
    | select(.artifacts_file.filename != null)
    | {
        name,
        size: .artifacts_file.size,
        expired: (.artifacts_expire_at != null and .artifacts_expire_at < $now),
        url: (.web_url + "/artifacts/download"),
        job: .id
    }];
'

gitlab_ci_no_workflow() {
    [ -z "${opt_workflow:-}" ] ||
        forge_unsupported "--workflow (GitLab has one pipeline definition per project)"
}

# Usage: gitlab_ci_post_json <endpoint> <json>  — POSTs a JSON body, prints the answer.
gitlab_ci_post_json() {
    gl_ci_post_file=$(forge_tmp)
    printf '%s\n' "$2" >"$gl_ci_post_file"
    gl_ci_post_rc=0
    forge_capture gitlab_api -X POST "$1" -H 'Content-Type: application/json' \
        --input "$gl_ci_post_file" || gl_ci_post_rc=$?
    rm -f "$gl_ci_post_file"
    return "$gl_ci_post_rc"
}

# --- runs --------------------------------------------------------------------------------

gitlab_ci_run_list() {
    gitlab_ci_no_workflow
    if ! forge_json_mode; then
        set -- ci list -R "$FORGE_R" --per-page "$opt_limit"
        [ -z "$opt_branch" ] || set -- "$@" --ref "$opt_branch"
        [ -z "$opt_status" ] || set -- "$@" --status "$opt_status"
        [ -z "$opt_sha" ] || set -- "$@" --sha "$opt_sha"
        [ -z "$opt_event" ] || set -- "$@" --source "$opt_event"
        forge_capture glab "$@"
        return
    fi
    gl_ci_q="$FORGE_API/pipelines?order_by=id&sort=desc"
    [ -z "$opt_branch" ] || gl_ci_q="$gl_ci_q&ref=$(forge_urlencode "$opt_branch")"
    [ -z "$opt_status" ] || gl_ci_q="$gl_ci_q&status=$opt_status"
    [ -z "$opt_sha" ] || gl_ci_q="$gl_ci_q&sha=$(forge_urlencode "$opt_sha")"
    [ -z "$opt_event" ] || gl_ci_q="$gl_ci_q&source=$(forge_urlencode "$opt_event")"
    gl_ci_list=$(gitlab_api_limit "$gl_ci_q" "$opt_limit") || return $?
    forge_emit_doc "$gl_ci_list" "$GL_CI_DEF [.[] | gl_ci_run]"
}

gitlab_ci_run_view() {
    forge_capture glab ci get -R "$FORGE_R" --pipeline-id "$1"
}

gitlab_ci_run_get() {
    gl_ci_run=$(forge_capture gitlab_api "$FORGE_API/pipelines/$1") || return $?
    forge_emit_doc "$gl_ci_run" "$GL_CI_DEF gl_ci_run"
}

gitlab_ci_run_latest() {
    gitlab_ci_no_workflow
    gl_ci_latest=$(forge_capture gitlab_api \
        "$FORGE_API/pipelines?ref=$(forge_urlencode "$1")&order_by=id&sort=desc&per_page=1") || return $?
    printf '%s\n' "$gl_ci_latest" | _jq -r '.[0].id // empty'
}

# GitLab has no "rerun everything": retry restarts the failed and canceled jobs.
gitlab_ci_run_retry() {
    forge_capture gitlab_api -X POST "$FORGE_API/pipelines/$1/retry" >/dev/null
}

gitlab_ci_run_cancel() {
    forge_capture gitlab_api -X POST "$FORGE_API/pipelines/$1/cancel" >/dev/null
}

gitlab_ci_run_delete() {
    forge_capture gitlab_api -X DELETE "$FORGE_API/pipelines/$1" >/dev/null
}

# Variables are an array of objects, which glab api -f cannot express; the body goes as JSON.
gitlab_ci_run_trigger() {
    gitlab_ci_no_workflow
    gl_ci_ref=$opt_ref
    if [ -z "$gl_ci_ref" ]; then
        gl_ci_project=$(forge_capture gitlab_api "$FORGE_API") || return $?
        gl_ci_ref=$(printf '%s\n' "$gl_ci_project" | _jq -r '.default_branch // empty')
        [ -n "$gl_ci_ref" ] || forge_die "the project has no default branch; pass --ref"
    fi
    gl_ci_body=$(printf '%s\n' "$opt_inputs" | _jq -R 'select(length > 0)
        | index("=") as $i | {key: .[:$i], value: .[$i + 1:]}' |
        _jq -sc --arg ref "$gl_ci_ref" '{ref: $ref, variables: .}')
    gl_ci_new=$(gitlab_ci_post_json "$FORGE_API/pipeline" "$gl_ci_body") || return $?
    printf '%s\n' "$gl_ci_new" | _jq -r '.id'
}

# --- jobs --------------------------------------------------------------------------------

gitlab_ci_job_list() {
    if ! forge_json_mode; then
        forge_capture glab ci get -R "$FORGE_R" --pipeline-id "$1" --with-job-details
        return
    fi
    gl_ci_jobs=$(forge_capture gitlab_api_all "$FORGE_API/pipelines/$1/jobs?per_page=100") || return $?
    forge_emit_doc "$gl_ci_jobs" "$GL_CI_DEF [.[] | gl_ci_job]"
}

# glab has no job view, so text mode prints the fields one per line.
gitlab_ci_job_view() {
    gl_ci_job=$(forge_capture gitlab_api "$FORGE_API/jobs/$1") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_ci_job" "$GL_CI_DEF gl_ci_job + {run_id: .pipeline.id}"
    else
        printf '%s\n' "$gl_ci_job" | _jq -r "$FORGE_JQ_DEFS $GL_CI_DEF
            gl_ci_job + {run_id: .pipeline.id, ref, sha: .commit.id}
            | to_entries[] | \"\\(.key): \\(if .value == null then \"\" else .value end)\""
    fi
}

gitlab_ci_job_log() {
    forge_capture gitlab_api "$FORGE_API/jobs/$1/trace"
}

gitlab_ci_job_retry() {
    gl_ci_new=$(forge_capture gitlab_api -X POST "$FORGE_API/jobs/$1/retry") || return $?
    printf '%s\n' "$gl_ci_new" | _jq -c '{run_id: .pipeline.id, job_id: .id}'
}

gitlab_ci_job_cancel() {
    gl_ci_job=$(forge_capture gitlab_api -X POST "$FORGE_API/jobs/$1/cancel") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_ci_job" "$GL_CI_DEF gl_ci_job"
    else
        printf '%s\n' "$1"
    fi
}

# --- artifacts ---------------------------------------------------------------------------

gitlab_ci_artifacts_doc() {
    gl_ci_jobs=$(forge_capture gitlab_api_all "$FORGE_API/pipelines/$1/jobs?per_page=100") || return $?
    printf '%s\n' "$gl_ci_jobs" | _jq "$GL_CI_DEF gl_ci_artifacts"
}

gitlab_ci_artifact_list() {
    gl_ci_arts=$(gitlab_ci_artifacts_doc "$1") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_ci_arts" '.'
    else
        printf '%s\n' "$gl_ci_arts" | _jq -r '.[].name'
    fi
}

gitlab_ci_artifact_download() {
    gl_ci_arts=$(gitlab_ci_artifacts_doc "$1") || return $?
    # A retried job keeps its name; the newest attempt is the one that counts.
    gl_ci_pick=$(printf '%s\n' "$gl_ci_arts" | _jq -r --arg n "$opt_name" '
        [.[] | select($n == "" or .name == $n)] | group_by(.name) | map(max_by(.job))[]
        | "\(.job)\t\(.name)"')
    if [ -z "$gl_ci_pick" ]; then
        [ -z "$opt_name" ] || forge_not_found "run $1 has no job named '$opt_name' with artifacts"
        forge_not_found "run $1 published no artifacts"
    fi
    gl_ci_tab=$(printf '\t')
    while IFS="$gl_ci_tab" read -r gl_ci_job gl_ci_name; do
        # Job names may hold "/", ":" or spaces; the file name may not.
        gl_ci_file="$opt_dir/$(printf '%s' "$gl_ci_name" | tr '/: []' '_____').zip"
        forge_capture gitlab_api "$FORGE_API/jobs/$gl_ci_job/artifacts" >"$gl_ci_file" || {
            gl_ci_rc=$?
            rm -f "$gl_ci_file"
            return "$gl_ci_rc"
        }
    done <<EOF
$gl_ci_pick
EOF
}

# --- lint --------------------------------------------------------------------------------

gitlab_ci_lint() {
    [ -f "$1" ] || forge_die "file not found: $1"
    if ! forge_json_mode; then
        forge_capture glab ci lint "$1" -R "$FORGE_R"
        return
    fi
    gl_ci_body=$(_jq -Rsc '{content: .}' <"$1") || forge_die "cannot read $1"
    gl_ci_lint=$(gitlab_ci_post_json "$FORGE_API/ci/lint" "$gl_ci_body") || return $?
    forge_emit_doc "$gl_ci_lint" '{valid, errors: (.errors // []), warnings: (.warnings // [])}'
    printf '%s\n' "$gl_ci_lint" | _jq -e '.valid == true' >/dev/null || return 1
}
