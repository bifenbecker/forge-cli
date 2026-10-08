# shellcheck shell=sh

GH_CI_RUN_FIELDS=databaseId,workflowName,status,conclusion,headBranch,headSha,event,url,createdAt,updatedAt

# gh reports a job that has not started yet with the zero time 0001-01-01T00:00:00Z.
GH_CI_DEF='
def gh_time: if . == null or . == "" or startswith("0001-") then null else . end;
def gh_ci_run: {
    id: .databaseId,
    name: .workflowName,
    status: gh_run_status,
    ref: .headBranch,
    sha: .headSha,
    event,
    url,
    created_at: .createdAt,
    updated_at: .updatedAt
};
def gh_ci_job($stage): {
    id: .databaseId,
    name,
    stage: $stage,
    status: gh_run_status,
    allow_failure: null,
    url,
    started_at: (.startedAt | gh_time),
    finished_at: (.completedAt | gh_time)
};
def gh_ci_rest_job: {
    id,
    name,
    stage: .workflow_name,
    status: gh_run_status,
    allow_failure: null,
    url: .html_url,
    started_at: (.started_at | gh_time),
    finished_at: (.completed_at | gh_time),
    run_id
};
'

# forge statuses to the run list filter. GitHub has no manual state.
github_ci_status_param() {
    case $1 in
        failed) printf 'failure' ;;
        running) printf 'in_progress' ;;
        pending) printf 'queued' ;;
        canceled) printf 'cancelled' ;;
        manual) forge_unsupported "--status manual" ;;
        *) printf '%s' "$1" ;;
    esac
}

# --- runs --------------------------------------------------------------------------------

github_ci_run_list() {
    set -- run list -R "$FORGE_R" --limit "$opt_limit"
    [ -z "$opt_branch" ] || set -- "$@" --branch "$opt_branch"
    if [ -n "$opt_status" ]; then
        gh_ci_status=$(github_ci_status_param "$opt_status") || exit $?
        set -- "$@" --status "$gh_ci_status"
    fi
    [ -z "$opt_sha" ] || set -- "$@" --commit "$opt_sha"
    [ -z "$opt_event" ] || set -- "$@" --event "$opt_event"
    [ -z "$opt_workflow" ] || set -- "$@" --workflow "$opt_workflow"
    if forge_json_mode; then
        gh_ci_list=$(forge_capture gh "$@" --json "$GH_CI_RUN_FIELDS") || return $?
        forge_emit_doc "$gh_ci_list" "$GH_CI_DEF [.[] | gh_ci_run]"
    else
        forge_capture gh "$@"
    fi
}

github_ci_run_view() {
    forge_capture gh run view "$1" -R "$FORGE_R"
}

github_ci_run_get() {
    gh_ci_run=$(forge_capture gh run view "$1" -R "$FORGE_R" --json "$GH_CI_RUN_FIELDS") || return $?
    forge_emit_doc "$gh_ci_run" "$GH_CI_DEF gh_ci_run"
}

# Prints the id of the newest run of branch $1, or nothing.
github_ci_run_latest() {
    set -- run list -R "$FORGE_R" --branch "$1" --limit 1 --json databaseId
    [ -z "$opt_workflow" ] || set -- "$@" --workflow "$opt_workflow"
    gh_ci_latest=$(forge_capture gh "$@") || return $?
    printf '%s\n' "$gh_ci_latest" | _jq -r '.[0].databaseId // empty'
}

github_ci_run_retry() {
    set -- run rerun "$1" -R "$FORGE_R"
    [ -z "$opt_failed" ] || set -- "$@" --failed
    forge_capture gh "$@" >/dev/null
}

github_ci_run_cancel() {
    forge_capture gh run cancel "$1" -R "$FORGE_R" >/dev/null
}

github_ci_run_delete() {
    forge_capture github_api -X DELETE "$FORGE_API/actions/runs/$1" >/dev/null
}

# Prints the id of the new run, or nothing when gh did not say.
github_ci_run_trigger() {
    [ -n "$opt_workflow" ] || forge_usage_die "--workflow is required on GitHub: the workflow file or name to run"
    set -- workflow run "$opt_workflow" -R "$FORGE_R"
    [ -z "$opt_ref" ] || set -- "$@" --ref "$opt_ref"
    while IFS= read -r gh_ci_input; do
        [ -z "$gh_ci_input" ] || set -- "$@" --raw-field "$gh_ci_input"
    done <<EOF
$opt_inputs
EOF
    # The run URL may come on stdout or stderr depending on the gh version, so forge_capture,
    # which drops stderr on success, does not fit here.
    gh_ci_err=$(forge_tmp)
    gh_ci_out=$(gh "$@" 2>"$gh_ci_err") || {
        gh_ci_rc=$?
        cat "$gh_ci_err" >&2
        # "could not find any workflows named ..." is gh's own wording for a missing workflow.
        if forge_err_not_found "$gh_ci_err" || grep -qi 'could not find' "$gh_ci_err"; then
            gh_ci_rc=$FORGE_EXIT_NOT_FOUND
        fi
        rm -f "$gh_ci_err"
        return "$gh_ci_rc"
    }
    gh_ci_out="$gh_ci_out
$(cat "$gh_ci_err")"
    rm -f "$gh_ci_err"
    gh_ci_url=$(printf '%s\n' "$gh_ci_out" | grep -Eo 'https?://[^[:space:]]+/actions/runs/[0-9]+' | tail -n 1)
    if [ -z "$gh_ci_url" ]; then
        forge_warn "the run was requested, but gh did not report its id; find it with 'forge ci run list --workflow $opt_workflow'"
        return 0
    fi
    printf '%s\n' "${gh_ci_url##*/}"
}

# --- jobs --------------------------------------------------------------------------------

github_ci_job_list() {
    if ! forge_json_mode; then
        forge_capture gh run view "$1" -R "$FORGE_R"
        return
    fi
    gh_ci_jobs=$(forge_capture gh run view "$1" -R "$FORGE_R" --json workflowName,jobs) || return $?
    forge_emit_doc "$gh_ci_jobs" "$GH_CI_DEF .workflowName as \$wf | [.jobs[] | gh_ci_job(\$wf)]"
}

github_ci_job_view() {
    if ! forge_json_mode; then
        forge_capture gh run view -R "$FORGE_R" --job "$1"
        return
    fi
    gh_ci_job=$(forge_capture github_api "$FORGE_API/actions/jobs/$1") || return $?
    forge_emit_doc "$gh_ci_job" "$GH_CI_DEF gh_ci_rest_job"
}

github_ci_job_log() {
    forge_capture gh run view -R "$FORGE_R" --job "$1" --log
}

# The new attempt's job id is not known until GitHub queues it, so job_id is null.
github_ci_job_retry() {
    gh_ci_job=$(forge_capture github_api "$FORGE_API/actions/jobs/$1") || return $?
    forge_capture gh run rerun -R "$FORGE_R" --job "$1" >/dev/null || return $?
    printf '%s\n' "$gh_ci_job" | _jq -c '{run_id, job_id: null}'
}

# --- artifacts ---------------------------------------------------------------------------

github_ci_artifacts_doc() {
    gh_ci_art=$(forge_capture github_api "$FORGE_API/actions/runs/$1/artifacts?per_page=100" \
        --paginate --jq '.artifacts[]') || return $?
    printf '%s\n' "$gh_ci_art" | _jq -s --arg web "$(github_web_url)/actions/runs/$1/artifacts" \
        '[.[] | {name, size: .size_in_bytes, expired, url: ($web + "/" + (.id | tostring)), job: null}]'
}

github_ci_artifact_list() {
    gh_ci_arts=$(github_ci_artifacts_doc "$1") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gh_ci_arts" '.'
    else
        printf '%s\n' "$gh_ci_arts" | _jq -r '.[].name'
    fi
}

github_ci_artifact_download() {
    if [ -n "$opt_name" ]; then
        # gh's own message for a missing name is not a "not found" one; check first for exit 4.
        gh_ci_arts=$(github_ci_artifacts_doc "$1") || return $?
        printf '%s\n' "$gh_ci_arts" | _jq -e --arg n "$opt_name" 'any(.[]; .name == $n)' >/dev/null ||
            forge_not_found "run $1 has no artifact named '$opt_name'"
    fi
    set -- run download "$1" -R "$FORGE_R" --dir "$opt_dir"
    [ -z "$opt_name" ] || set -- "$@" --name "$opt_name"
    forge_capture gh "$@" >&2
}

github_ci_run_trigger_request() {
    forge_unsupported "--request (no GitHub API starts a pull_request run: push, mark the request ready, or use 'forge ci run retry <run-id>')"
}
