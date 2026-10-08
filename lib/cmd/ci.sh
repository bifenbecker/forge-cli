# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/ci.sh

CI_RUN_SHAPE='{id, name, status, ref, sha, event, url, created_at, updated_at}'
CI_JOB_SHAPE='{id, name, stage, status, allow_failure, url, started_at, finished_at}'
CI_ARTIFACT_SHAPE='{name, size, expired, url, job}'
CI_STATUS_NOTE='status is success, failed, running, pending, manual, canceled or skipped.'

help_ci() {
    cat <<'EOF'
forge ci - CI runs, jobs and artifacts

A run is a GitHub Actions workflow run or a GitLab pipeline; a job is a job on both.
<run-id> and <job-id> are the numeric ids the host shows (databaseId on GitHub).

COMMANDS
  run         Runs: list, view, status, watch, retry, cancel, delete, trigger
  job         Jobs of a run: list, view, log, retry, cancel
  artifact    Artifacts of a run: list, download
  lint        Validate a .gitlab-ci.yml (GitLab only)

Run 'forge ci <command> --help' for details.
EOF
}

help_ci_run() {
    cat <<'EOF'
forge ci run - CI runs: GitHub workflow runs, GitLab pipelines

COMMANDS
  list        List runs, newest first
  view        Show one run
  status      Status of the newest run of a branch
  watch       Wait until a run finishes; exit 1 unless it succeeded
  retry       Run a finished run again
  cancel      Cancel a running run
  delete      Delete a run
  trigger     Start a new run

Run 'forge ci run <command> --help' for details.
EOF
}

help_ci_job() {
    cat <<'EOF'
forge ci job - jobs of a CI run

COMMANDS
  list        Jobs of a run
  view        Show one job
  log         Print the log of a job
  retry       Run one job again
  cancel      Cancel one job (GitLab only)

Run 'forge ci job <command> --help' for details.
EOF
}

help_ci_artifact() {
    cat <<'EOF'
forge ci artifact - files a CI run published

COMMANDS
  list        Artifacts of a run
  download    Download artifacts of a run

Run 'forge ci artifact <command> --help' for details.
EOF
}

# Usage: ci_take_id <name> <value>  — a run or job id is required and numeric.
ci_take_id() {
    [ -n "$2" ] || forge_usage_die "$1 is required"
    forge_require_int "$1" "$2"
}

# Sets ci_run_doc_out to the normalised run, ignoring the user's --jq.
ci_run_doc() {
    ci_run_doc_out=$(FORGE_JQ=''; forge_call ci_run_get "$1") || return $?
    ci_run_doc_status=$(printf '%s\n' "$ci_run_doc_out" | _jq -r '.status')
}

# After an action on a run: its id in text mode, the run in JSON mode.
ci_run_report() {
    if forge_json_mode; then
        forge_call ci_run_get "$1"
    else
        printf '%s\n' "$1"
    fi
}

# --- run list ----------------------------------------------------------------------------

help_ci_run_list() {
    cat <<EOF
NAME
  forge ci run list - list CI runs

USAGE
  forge ci run list [--branch <name>] [--status <status>] [--sha <commit>] [--event <event>]
                    [--workflow <file|name>] [--limit <n>]

DESCRIPTION
  Lists runs of the repository, newest first. Filters combine with AND.

FLAGS
  -b, --branch <name>      Runs of this branch (GitLab: ref, so a tag works too)
  -s, --status <status>    success, failed, running, pending, canceled, skipped or manual
  --sha <commit>           Runs of this commit (full SHA)
  --event <event>          What started the run, in the host's own words (see PLATFORM NOTES);
                           --source is the same flag
  -w, --workflow <name>    Runs of this workflow file or name (GitHub only)
  -L, --limit <n>          At most this many runs (default 20)

OUTPUT
  Text: the platform CLI's table. On GitLab with --limit above 100 (one glab page), forge's
        own: one pipeline per line, tab-separated: id, status, ref, created_at.
  JSON: array of $CI_RUN_SHAPE
  $CI_STATUS_NOTE

PLATFORM NOTES
  GitHub: each workflow is its own run, so one push gives several runs. name is the workflow
          name. --status failed matches conclusion "failure" only (not timed_out or
          startup_failure); pending matches "queued" only. --status manual exits 3.
          --event: push, pull_request, workflow_dispatch, schedule, issue_comment, ...
  GitLab: one pipeline per push. name is the pipeline name, often null. --workflow exits 3.
          --event is the pipeline source: push, web, api, schedule, merge_request_event,
          trigger, pipeline, parent_pipeline, ...

EXAMPLES
  forge ci run list
  forge ci run list --branch main --status failed --limit 5 --json
  forge ci run list --sha "\$(git rev-parse HEAD)" --jq '.[] | {id, status}'
  forge ci run list --workflow test.yml
EOF
}

cmd_ci_run_list() {
    opt_branch='' opt_status='' opt_sha='' opt_event='' opt_workflow='' opt_limit=20
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --branch) forge_arg "$@"; opt_branch=$2; shift 2 ;;
            -s | --status) forge_arg "$@"; opt_status=$2; shift 2 ;;
            --sha) forge_arg "$@"; opt_sha=$2; shift 2 ;;
            --event | --source) forge_arg "$@"; opt_event=$2; shift 2 ;;
            -w | --workflow) forge_arg "$@"; opt_workflow=$2; shift 2 ;;
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    [ -z "$opt_status" ] ||
        forge_require_one_of --status "$opt_status" success failed running pending canceled skipped manual
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    forge_call ci_run_list
}

# --- run view ----------------------------------------------------------------------------

help_ci_run_view() {
    cat <<EOF
NAME
  forge ci run view - show one CI run

USAGE
  forge ci run view <run-id>

DESCRIPTION
  Shows the status, branch, commit and trigger of a run. Jobs are listed by 'forge ci job list'.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab), not the pipeline iid

OUTPUT
  Text: the platform CLI's view, with its jobs.
  JSON: $CI_RUN_SHAPE
  $CI_STATUS_NOTE

PLATFORM NOTES
  GitHub: status comes from the conclusion once the run completed. name is the workflow name.
  GitLab: event is the pipeline source; name is the pipeline name, often null.

EXAMPLES
  forge ci run view 123456789
  forge ci run view 123456789 --jq .status
EOF
}

cmd_ci_run_view() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    if forge_json_mode; then
        forge_call ci_run_get "$arg_id"
    else
        forge_call ci_run_view "$arg_id"
    fi
}

# --- run status --------------------------------------------------------------------------

help_ci_run_status() {
    cat <<EOF
NAME
  forge ci run status - status of the newest run of a branch

USAGE
  forge ci run status [--branch <name>] [--workflow <file|name>]

DESCRIPTION
  Finds the newest run of a branch and reports its status. Does not wait; see 'forge ci run
  watch'.

FLAGS
  -b, --branch <name>      Branch to look at (default: the current branch; required
                           with --repo)
  -w, --workflow <name>    Only runs of this workflow file or name (GitHub only)

OUTPUT
  Text: the status alone, one word.
  JSON: $CI_RUN_SHAPE
  $CI_STATUS_NOTE
  Exit 4 when the branch has no run.

PLATFORM NOTES
  GitHub: every workflow is its own run; without --workflow this is the newest run of any
          workflow, which may not be the one you care about.
  GitLab: the newest pipeline of the ref. --workflow exits 3.

EXAMPLES
  forge ci run status
  forge ci run status --branch main --json
  forge ci run status --workflow test.yml --jq .id
EOF
}

cmd_ci_run_status() {
    opt_branch='' opt_workflow=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --branch) forge_arg "$@"; opt_branch=$2; shift 2 ;;
            -w | --workflow) forge_arg "$@"; opt_workflow=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    if [ -z "$opt_branch" ]; then
        [ -z "$FORGE_REPO_FLAG" ] || forge_usage_die "with --repo, pass --branch <name>"
        opt_branch=$(forge_current_branch)
        [ -n "$opt_branch" ] || forge_usage_die "HEAD is detached: pass --branch <name>"
    fi
    ci_status_id=$(forge_call ci_run_latest "$opt_branch") || exit $?
    [ -n "$ci_status_id" ] || forge_not_found "no CI run for branch '$opt_branch'"
    if forge_json_mode; then
        forge_call ci_run_get "$ci_status_id"
        return
    fi
    ci_run_doc "$ci_status_id" || exit $?
    printf '%s\n' "$ci_run_doc_status"
}

# --- run watch ---------------------------------------------------------------------------

help_ci_run_watch() {
    cat <<EOF
NAME
  forge ci run watch - wait until a CI run finishes

USAGE
  forge ci run watch <run-id> [--interval <s>]

DESCRIPTION
  Polls the run until its status is no longer pending or running, then reports it.
  Each change of status is noted on stderr. Exits 1 unless the run succeeded or was skipped,
  so 'forge ci run watch <id> && deploy' is safe.

ARGUMENTS
  <run-id>          Workflow run id (GitHub) or pipeline id (GitLab)

FLAGS
  --interval <s>    Seconds between polls (default 15)

OUTPUT
  Text: the final status alone, one word.
  JSON: $CI_RUN_SHAPE
  $CI_STATUS_NOTE

PLATFORM NOTES
  GitHub: a run waiting for an environment approval stays pending, and watch keeps waiting.
  GitLab: a pipeline blocked on a manual job ends the watch with status manual and exit 1.

EXAMPLES
  forge ci run watch 123456789
  forge ci run watch "\$(forge ci run trigger --workflow deploy.yml)" --interval 30
  forge ci run watch 123456789 --jq '{status, url}'
EOF
}

cmd_ci_run_watch() {
    arg_id='' opt_interval=15
    while [ $# -gt 0 ]; do
        case $1 in
            --interval) forge_arg "$@"; opt_interval=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_require_int --interval "$opt_interval"
    ci_watch_last=''
    while :; do
        ci_run_doc "$arg_id" || exit $?
        if [ "$ci_run_doc_status" != "$ci_watch_last" ]; then
            forge_warn "run $arg_id is $ci_run_doc_status"
            ci_watch_last=$ci_run_doc_status
        fi
        case $ci_run_doc_status in
            pending | running) sleep "$opt_interval" ;;
            *) break ;;
        esac
    done
    if forge_json_mode; then
        forge_emit_doc "$ci_run_doc_out" '.'
    else
        printf '%s\n' "$ci_run_doc_status"
    fi
    case $ci_run_doc_status in
        success | skipped) ;;
        *) exit 1 ;;
    esac
}

# --- run retry / cancel / delete ---------------------------------------------------------

help_ci_run_retry() {
    cat <<EOF
NAME
  forge ci run retry - run a finished CI run again

USAGE
  forge ci run retry <run-id> [--failed]

DESCRIPTION
  Starts the run's jobs again in the same run; the run id does not change, so the result
  can be passed straight to 'forge ci run watch'.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab)

FLAGS
  --failed      Only the failed jobs (and, on GitHub, the jobs they depend on)

OUTPUT
  Text: the run id.
  JSON: $CI_RUN_SHAPE

PLATFORM NOTES
  GitHub: a new attempt of the run; without --failed every job runs again. GitHub refuses
          to rerun a run that is still in progress.
  GitLab: always retries only the failed and canceled jobs; --failed changes nothing. To run
          every job again, start a new pipeline with 'forge ci run trigger'.

EXAMPLES
  forge ci run retry 123456789 --failed
  forge ci run retry 123456789 && forge ci run watch 123456789
EOF
}

cmd_ci_run_retry() {
    arg_id='' opt_failed=''
    while [ $# -gt 0 ]; do
        case $1 in
            --failed) opt_failed=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_call ci_run_retry "$arg_id" || exit $?
    ci_run_report "$arg_id"
}

help_ci_run_cancel() {
    cat <<EOF
NAME
  forge ci run cancel - cancel a CI run

USAGE
  forge ci run cancel <run-id>

DESCRIPTION
  Asks the host to cancel every unfinished job of the run. Cancelling takes a moment: the
  status right after may still be running.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab)

OUTPUT
  Text: the run id.
  JSON: $CI_RUN_SHAPE

PLATFORM NOTES
  GitHub: cancelling a completed run fails with exit 1.
  GitLab: cancelling a finished pipeline is accepted and changes nothing.

EXAMPLES
  forge ci run cancel 123456789
EOF
}

cmd_ci_run_cancel() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_call ci_run_cancel "$arg_id" || exit $?
    ci_run_report "$arg_id"
}

help_ci_run_delete() {
    cat <<'EOF'
NAME
  forge ci run delete - delete a CI run

USAGE
  forge ci run delete <run-id>

DESCRIPTION
  Deletes the run with its jobs, logs and artifacts. It cannot be undone and asks nothing.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab)

OUTPUT
  Nothing; the exit code tells. Exit 4 when the run does not exist.

PLATFORM NOTES
  GitHub: a run still in progress cannot be deleted; cancel it first.
  GitLab: needs the Owner role on the project.

EXAMPLES
  forge ci run delete 123456789
EOF
}

cmd_ci_run_delete() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_call ci_run_delete "$arg_id"
}

# --- run trigger -------------------------------------------------------------------------

help_ci_run_trigger() {
    cat <<EOF
NAME
  forge ci run trigger - start a new CI run

USAGE
  forge ci run trigger [--ref <branch>] [--workflow <file|name>] [--input <key=value>]...

DESCRIPTION
  Starts a run on a branch or tag and prints its id, ready for 'forge ci run watch'.
  The ref must exist on the host: push the branch first.

FLAGS
  --ref <branch>             Branch or tag (default: the current branch; with a detached
                             HEAD or --repo, the repository's default branch)
  -w, --workflow <name>      Workflow file (deploy.yml) or name to run; required on GitHub
  -i, --input <key=value>    Input of the run; repeat for several (see PLATFORM NOTES)

OUTPUT
  Text: the new run id.
  JSON: $CI_RUN_SHAPE

PLATFORM NOTES
  GitHub: runs a workflow_dispatch event; the workflow must declare 'on: workflow_dispatch'
          and every --input must be one of its declared inputs. Without --workflow: exit 2.
          If gh does not report the new run, a warning is printed and the output is empty.
  GitLab: creates a pipeline; each --input becomes a CI/CD variable (not a spec:inputs
          input). --workflow exits 3.

EXAMPLES
  forge ci run trigger --workflow deploy.yml --ref main --input environment=staging
  forge ci run trigger --input DEPLOY=1 --json
  id=\$(forge ci run trigger --workflow test.yml) && forge ci run watch "\$id"
EOF
}

cmd_ci_run_trigger() {
    opt_ref='' opt_workflow='' opt_inputs=''
    while [ $# -gt 0 ]; do
        case $1 in
            --ref) forge_arg "$@"; opt_ref=$2; shift 2 ;;
            -w | --workflow) forge_arg "$@"; opt_workflow=$2; shift 2 ;;
            -i | --input)
                forge_arg "$@"
                case $2 in
                    ?*=*) ;;
                    *) forge_usage_die "--input must be key=value, got '$2'" ;;
                esac
                opt_inputs=$(forge_list_add "$opt_inputs" "$2")
                shift 2
                ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    # The current branch means something only for the checkout's own repository.
    [ -n "$opt_ref" ] || [ -n "$FORGE_REPO_FLAG" ] || opt_ref=$(forge_current_branch)
    ci_trigger_id=$(forge_call ci_run_trigger) || exit $?
    [ -n "$ci_trigger_id" ] || return 0
    ci_run_report "$ci_trigger_id"
}

# --- job ---------------------------------------------------------------------------------

help_ci_job_list() {
    cat <<EOF
NAME
  forge ci job list - jobs of a CI run

USAGE
  forge ci job list <run-id>

DESCRIPTION
  Lists the jobs of a run, latest attempt only. Job ids feed 'forge ci job log|view|retry'.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab)

OUTPUT
  Text: the platform CLI's view of the run, which shows each job with its id.
  JSON: array of $CI_JOB_SHAPE
  $CI_STATUS_NOTE

PLATFORM NOTES
  GitHub: stage is the workflow name; allow_failure is null (GitHub has no such flag).
  GitLab: trigger jobs (bridges to downstream pipelines) are not included.

EXAMPLES
  forge ci job list 123456789
  forge ci job list 123456789 --jq '.[] | select(.status == "failed") | .id'
EOF
}

cmd_ci_job_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_call ci_job_list "$arg_id"
}

help_ci_job_view() {
    cat <<EOF
NAME
  forge ci job view - show one CI job

USAGE
  forge ci job view <job-id>

DESCRIPTION
  Shows the status, stage and timing of a job.

ARGUMENTS
  <job-id>      Job id, as 'forge ci job list' reports it

OUTPUT
  Text: GitHub: gh's view of the job with its steps. GitLab: one "key: value" per line.
  JSON: $CI_JOB_SHAPE
        plus run_id (the run the job belongs to).
  $CI_STATUS_NOTE

PLATFORM NOTES
  GitHub: stage is the workflow name; allow_failure is null.

EXAMPLES
  forge ci job view 987654321
  forge ci job view 987654321 --jq .status
EOF
}

cmd_ci_job_view() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<job-id>" "$arg_id"
    forge_call ci_job_view "$arg_id"
}

help_ci_job_log() {
    cat <<'EOF'
NAME
  forge ci job log - print the log of a CI job

USAGE
  forge ci job log <job-id>

DESCRIPTION
  Prints the whole log of one job to stdout.

ARGUMENTS
  <job-id>      Job id, as 'forge ci job list' reports it

OUTPUT
  Text and JSON: the raw log. --json and --jq do not apply.

PLATFORM NOTES
  GitHub: the log exists only once the job completed; before that the command exits 1.
          Each line is prefixed by gh with "<job>\t<step>\t".
  GitLab: works while the job runs and shows the log so far, with ANSI colour codes.

EXAMPLES
  forge ci job log 987654321
  forge ci job log 987654321 | tail -n 50
EOF
}

cmd_ci_job_log() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<job-id>" "$arg_id"
    forge_call ci_job_log "$arg_id"
}

help_ci_job_retry() {
    cat <<'EOF'
NAME
  forge ci job retry - run one CI job again

USAGE
  forge ci job retry <job-id>

DESCRIPTION
  Starts the job again and prints the run it belongs to, ready for 'forge ci run watch'.

ARGUMENTS
  <job-id>      Job id, as 'forge ci job list' reports it

OUTPUT
  Text: the run id.
  JSON: {run_id, job_id}; job_id is the id of the new job, or null where it is not known yet.

PLATFORM NOTES
  GitHub: starts a new attempt of the run with this job and the jobs it depends on; the
          job must have finished. job_id is null: the new job gets its id once it is queued.
  GitLab: creates a new job in the same pipeline; job_id is its id.

EXAMPLES
  forge ci job retry 987654321
  forge ci run watch "$(forge ci job retry 987654321)"
EOF
}

cmd_ci_job_retry() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<job-id>" "$arg_id"
    ci_job_retry_doc=$(FORGE_JQ=''; forge_call ci_job_retry "$arg_id") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$ci_job_retry_doc" '.'
    else
        printf '%s\n' "$ci_job_retry_doc" | _jq -r '.run_id'
    fi
}

help_ci_job_cancel() {
    cat <<EOF
NAME
  forge ci job cancel - cancel one CI job

USAGE
  forge ci job cancel <job-id>

DESCRIPTION
  Cancels one running or pending job; the rest of the run goes on.

ARGUMENTS
  <job-id>      Job id, as 'forge ci job list' reports it

OUTPUT
  Text: the job id.
  JSON: $CI_JOB_SHAPE

PLATFORM NOTES
  GitHub: not supported (exit 3): GitHub cancels whole runs only; use 'forge ci run cancel'.

EXAMPLES
  forge ci job cancel 987654321
EOF
}

cmd_ci_job_cancel() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<job-id>" "$arg_id"
    forge_call ci_job_cancel "$arg_id"
}

# --- artifact ----------------------------------------------------------------------------

help_ci_artifact_list() {
    cat <<EOF
NAME
  forge ci artifact list - artifacts of a CI run

USAGE
  forge ci artifact list <run-id>

DESCRIPTION
  Lists what the run published. The names are what 'forge ci artifact download --name' takes.

ARGUMENTS
  <run-id>      Workflow run id (GitHub) or pipeline id (GitLab)

OUTPUT
  Text: one artifact name per line; nothing when the run published none.
  JSON: array of $CI_ARTIFACT_SHAPE
  size is in bytes; expired is true once the host deleted or will no longer serve the files;
  url is the web download address; job is the id of the job that made it, or null.

PLATFORM NOTES
  GitHub: artifacts belong to the run; each upload-artifact step makes one, named by the
          workflow. job is null.
  GitLab: artifacts belong to jobs; each job with artifacts is one entry, named after the
          job (a retried job keeps its name, so two entries may share a name). job is the
          job id.

EXAMPLES
  forge ci artifact list 123456789
  forge ci artifact list 123456789 --jq '.[] | select(.expired | not) | .name'
EOF
}

cmd_ci_artifact_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    forge_call ci_artifact_list "$arg_id"
}

help_ci_artifact_download() {
    cat <<'EOF'
NAME
  forge ci artifact download - download artifacts of a CI run

USAGE
  forge ci artifact download <run-id> [--name <name>] [--dir <path>]

DESCRIPTION
  Downloads every artifact of the run, or the one named, into a directory.

ARGUMENTS
  <run-id>          Workflow run id (GitHub) or pipeline id (GitLab)

FLAGS
  -n, --name <name>  Only this artifact: the name 'forge ci artifact list' shows
                     (GitHub: artifact name; GitLab: job name)
  -D, --dir <path>   Where the files go (default .tmp/ci-artifacts/<run-id>); created if missing

OUTPUT
  Text and JSON: the directory, one line. Exit 4 when nothing matches or nothing was published.

PLATFORM NOTES
  GitHub: artifacts are unpacked. With --name the files land directly in the directory;
          without it each artifact gets a subdirectory named after it.
  GitLab: each job's artifacts arrive as one <job>.zip, not unpacked ("/", ":", " ", "[",
          "]" in the job name become "_"). With --name and a retried job, the newest wins.

EXAMPLES
  forge ci artifact download 123456789
  forge ci artifact download 123456789 --name coverage --dir .tmp/coverage
EOF
}

cmd_ci_artifact_download() {
    arg_id='' opt_name='' opt_dir=''
    while [ $# -gt 0 ]; do
        case $1 in
            -n | --name) forge_arg "$@"; opt_name=$2; shift 2 ;;
            -D | --dir) forge_arg "$@"; opt_dir=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    ci_take_id "<run-id>" "$arg_id"
    opt_dir=${opt_dir:-.tmp/ci-artifacts/$arg_id}
    mkdir -p "$opt_dir" || forge_die "cannot create $opt_dir"
    forge_call ci_artifact_download "$arg_id" || exit $?
    printf '%s\n' "$opt_dir"
}

# --- lint --------------------------------------------------------------------------------

help_ci_lint() {
    cat <<'EOF'
NAME
  forge ci lint - validate a GitLab CI configuration

USAGE
  forge ci lint [<file>]

DESCRIPTION
  Sends the file to the host's CI linter, which checks it against this project
  (includes, templates). Exits 1 when the configuration is invalid or the file is missing.

ARGUMENTS
  <file>        Configuration to check (default .gitlab-ci.yml)

OUTPUT
  Text: glab's verdict.
  JSON: {valid, errors[], warnings[]}

PLATFORM NOTES
  GitHub: not supported (exit 3); GitHub has no workflow linter API.

EXAMPLES
  forge ci lint
  forge ci lint ci/pipeline.yml --jq .errors
EOF
}

cmd_ci_lint() {
    arg_file=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_file" ] || forge_unexpected "$1"; arg_file=$1; shift ;;
        esac
    done
    arg_file=${arg_file:-.gitlab-ci.yml}
    forge_call ci_lint "$arg_file"
}
