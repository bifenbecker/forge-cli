# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/request.sh

REQUEST_JSON_SHAPE='{id, title, state, draft, author, source_branch, target_branch, url,
         description, labels[], assignees[], reviewers[], sha, created_at, updated_at,
         merged_at, closed_at, mergeable}
  state is open, closed or merged. mergeable is true, false or null (not yet known).'

help_request() {
    cat <<'EOF'
forge request - pull requests (GitHub) and merge requests (GitLab)

Aliases: forge pr, forge mr. <id> is the PR number or the MR iid.
Where <id> is optional, the open request of the current branch is used.

COMMANDS
  list          List requests
  view          Show one request
  create        Open a request from a branch
  edit          Change title, description, target, labels, assignees, reviewers, milestone
  close         Close a request
  reopen        Reopen a closed request
  merge         Merge a request
  ready         Mark a draft ready for review, or back to draft
  checkout      Check a request out locally
  diff          Show the diff of a request
  approve       Approve a request
  checks        CI status of a request: one status and one entry per job
  id            Number of the open request for a branch
  url           Web address of a request
  ref           How a commit message names a request: #12 or !12
  fetch         Fetch a request's head into a local ref
  template      Path of the request description template
  comment       Comments: list, add, edit, inline
  thread        Review threads: list, reply, resolve, unresolve
  label         Labels of a request: list, add, remove
  reviewer      Reviewers of a request: add, remove
  suggestion    Fence for a suggested change in a comment

Run 'forge request <command> --help' for details.
EOF
}

# The open request of the current branch, or the given id.
request_resolve_id() {
    if [ -n "${1:-}" ]; then
        forge_require_int "<id>" "$1"
        printf '%s' "$1"
        return 0
    fi
    rri_branch=$(forge_current_branch)
    [ -n "$rri_branch" ] || forge_usage_die "HEAD is detached: pass the request <id>"
    rri_id=$(forge_call request_find "$rri_branch" open) || exit $?
    [ -n "$rri_id" ] || forge_not_found "no open request for branch '$rri_branch'"
    printf '%s' "$rri_id"
}

# After a change: the URL in text mode, the full request in JSON mode.
request_report() {
    if forge_json_mode; then
        forge_call request_view "$1"
    else
        forge_call request_url "$1"
    fi
}

# --- list --------------------------------------------------------------------------------

help_request_list() {
    cat <<EOF
NAME
  forge request list - list requests

USAGE
  forge request list [--state <state>] [--limit <n>] [--author <user>] [--assignee <user>]
                     [--label <name>]... [--source <branch>] [--target <branch>] [--draft]
                     [--search <text>]

DESCRIPTION
  Lists requests of the repository, newest first. Filters combine with AND.

FLAGS
  --state <state>      open (default), closed, merged or all
  -L, --limit <n>      At most this many requests (default 30)
  --author <user>      Opened by this user; @me for yourself
  --assignee <user>    Assigned to this user; @me for yourself
  --label <name>       Carrying this label; repeat for several
  --source <branch>    From this source (head) branch
  --target <branch>    Into this target (base) branch
  --draft              Only drafts
  --search <text>      Free-text search in title and description

OUTPUT
  Text: the platform CLI's table.
  JSON: array of $REQUEST_JSON_SHAPE

PLATFORM NOTES
  GitHub: --state closed excludes merged requests, as on GitLab.

EXAMPLES
  forge request list
  forge request list --state merged --limit 5 --json
  forge request list --source feature/login --jq '.[0].id'
  forge request list --author @me --label bug
EOF
}

cmd_request_list() {
    opt_state=open opt_limit=30 opt_author='' opt_assignee='' opt_labels='' opt_source='' opt_target=''
    opt_draft='' opt_search=''
    while [ $# -gt 0 ]; do
        case $1 in
            --state) forge_arg "$@"; opt_state=$2; shift 2 ;;
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            --author) forge_arg "$@"; opt_author=$2; shift 2 ;;
            --assignee) forge_arg "$@"; opt_assignee=$2; shift 2 ;;
            --label) forge_arg "$@"; opt_labels=$(forge_list_add "$opt_labels" "$2"); shift 2 ;;
            --source) forge_arg "$@"; opt_source=$2; shift 2 ;;
            --target) forge_arg "$@"; opt_target=$2; shift 2 ;;
            --draft) opt_draft=1; shift ;;
            --search) forge_arg "$@"; opt_search=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_one_of --state "$opt_state" open closed merged all
    forge_require_int --limit "$opt_limit"
    forge_call request_list
}

# --- view --------------------------------------------------------------------------------

help_request_view() {
    cat <<EOF
NAME
  forge request view - show one request

USAGE
  forge request view [<id>] [--comments] [--web]

DESCRIPTION
  Shows title, state, branches, description, people, approvals and mergeability of a request.

ARGUMENTS
  <id>          Request number; default: the open request of the current branch

FLAGS
  --comments    Text mode: include the comments
  --web         Open the request in the browser instead

OUTPUT
  Text: the platform CLI's view.
  JSON: $REQUEST_JSON_SHAPE
        plus approved (bool), approved_by[] (users who approved), decision
        (approved, changes_requested, review_required, or null where the host has no verdict).

PLATFORM NOTES
  GitLab: decision is always null; approvals come from the approvals endpoint.

EXAMPLES
  forge request view 42
  forge request view --json
  forge request view 42 --jq '{state, mergeable, approved}'
EOF
}

cmd_request_view() {
    arg_id='' opt_comments='' opt_web=''
    while [ $# -gt 0 ]; do
        case $1 in
            --comments) opt_comments=1; shift ;;
            --web) opt_web=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_call request_view "$arg_id"
}

# --- create ------------------------------------------------------------------------------

help_request_create() {
    cat <<EOF
NAME
  forge request create - open a request

USAGE
  forge request create --title <text> [--body <text> | --body-file <path|->]
                       [--target <branch>] [--source <branch>] [--draft]
                       [--assignee <user>]... [--reviewer <user>]... [--label <name>]...
                       [--milestone <name>] [--delete-branch] [--fill]

DESCRIPTION
  Opens a request from a branch that is already pushed. Fails if one is already open
  for the same source branch.

FLAGS
  --title <text>          Title; required unless --fill
  --body <text>           Description
  --body-file <path|->    Description from a file, or - for stdin
  --target <branch>       Branch to merge into; default: the repository default branch
  --source <branch>       Branch to merge from; default: the current branch
  --draft                 Open as a draft
  --assignee <user>       Assign; @me for yourself; repeatable
  --reviewer <user>       Ask for review; repeatable
  --label <name>          Add a label; repeatable
  --milestone <name>      Put in a milestone
  --delete-branch         Delete the source branch when merged
  --fill                  Take title and description from the commits

OUTPUT
  Text: the URL of the new request.
  JSON: the new request, as forge request view --json.

PLATFORM NOTES
  GitHub: --delete-branch is a repository setting ("Automatically delete head branches");
          the flag only prints a warning there. Use 'request merge --delete-branch' instead.
  GitHub: a missing label is created first, as GitLab does.

EXAMPLES
  forge request create --title "fix: handle empty input" --body-file .tmp/body.md --draft
  forge request create --title "feat: login" --target develop --assignee @me --json
EOF
}

cmd_request_create() {
    opt_title='' opt_target='' opt_source='' opt_draft='' opt_assignees='' opt_reviewers='' opt_labels=''
    opt_milestone='' opt_delete_branch='' opt_fill=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            --target | --base) forge_arg "$@"; opt_target=$2; shift 2 ;;
            --source | --head) forge_arg "$@"; opt_source=$2; shift 2 ;;
            --draft) opt_draft=1; shift ;;
            --assignee) forge_arg "$@"; opt_assignees=$(forge_list_add "$opt_assignees" "$2"); shift 2 ;;
            --reviewer) forge_arg "$@"; opt_reviewers=$(forge_list_add "$opt_reviewers" "$2"); shift 2 ;;
            --label) forge_arg "$@"; opt_labels=$(forge_list_add "$opt_labels" "$2"); shift 2 ;;
            --milestone) forge_arg "$@"; opt_milestone=$2; shift 2 ;;
            --delete-branch) opt_delete_branch=1; shift ;;
            --fill) opt_fill=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    [ -n "$opt_title" ] || [ -n "$opt_fill" ] || forge_usage_die "--title is required (or --fill)"
    if [ -z "$opt_source" ]; then
        opt_source=$(forge_current_branch)
        [ -n "$opt_source" ] || forge_usage_die "HEAD is detached: pass --source <branch>"
    fi
    request_create_id=$(forge_call request_create) || exit $?
    request_report "$request_create_id"
}

# --- edit --------------------------------------------------------------------------------

help_request_edit() {
    cat <<'EOF'
NAME
  forge request edit - change a request

USAGE
  forge request edit [<id>] [--title <text>] [--body <text> | --body-file <path|->]
                     [--target <branch>] [--milestone <name>]
                     [--add-label <name>]... [--remove-label <name>]...
                     [--add-assignee <user>]... [--remove-assignee <user>]...
                     [--add-reviewer <user>]... [--remove-reviewer <user>]...

DESCRIPTION
  Changes only what is given; everything else stays.

ARGUMENTS
  <id>                       Request number; default: the open request of the current branch

FLAGS
  --title <text>             New title
  --body <text>              New description
  --body-file <path|->       New description from a file, or - for stdin
  --target <branch>          New target branch
  --milestone <name>         Move to this milestone
  --add-label <name>         Add a label; repeatable
  --remove-label <name>      Remove a label; repeatable
  --add-assignee <user>      Add an assignee (@me for yourself); repeatable
  --remove-assignee <user>   Remove an assignee; repeatable
  --add-reviewer <user>      Ask for review; repeatable
  --remove-reviewer <user>   Withdraw a review request; repeatable

OUTPUT
  Text: the URL of the request.
  JSON: the request after the change, as forge request view --json.

EXAMPLES
  forge request edit 42 --title "fix: handle empty input (#42)"
  forge request edit --add-label ready --remove-label wip
  forge request edit 42 --body-file - < body.md
EOF
}

cmd_request_edit() {
    arg_id='' opt_title='' opt_target='' opt_milestone='' opt_add_labels='' opt_remove_labels=''
    opt_add_assignees='' opt_remove_assignees='' opt_add_reviewers='' opt_remove_reviewers=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            --target | --base) forge_arg "$@"; opt_target=$2; shift 2 ;;
            --milestone) forge_arg "$@"; opt_milestone=$2; shift 2 ;;
            --add-label) forge_arg "$@"; opt_add_labels=$(forge_list_add "$opt_add_labels" "$2"); shift 2 ;;
            --remove-label) forge_arg "$@"; opt_remove_labels=$(forge_list_add "$opt_remove_labels" "$2"); shift 2 ;;
            --add-assignee) forge_arg "$@"; opt_add_assignees=$(forge_list_add "$opt_add_assignees" "$2"); shift 2 ;;
            --remove-assignee) forge_arg "$@"; opt_remove_assignees=$(forge_list_add "$opt_remove_assignees" "$2"); shift 2 ;;
            --add-reviewer) forge_arg "$@"; opt_add_reviewers=$(forge_list_add "$opt_add_reviewers" "$2"); shift 2 ;;
            --remove-reviewer) forge_arg "$@"; opt_remove_reviewers=$(forge_list_add "$opt_remove_reviewers" "$2"); shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_call request_edit "$arg_id"
    request_report "$arg_id"
}

# --- close / reopen ----------------------------------------------------------------------

help_request_close() {
    cat <<'EOF'
NAME
  forge request close - close a request without merging it

USAGE
  forge request close [<id>] [--comment <text>] [--delete-branch]

DESCRIPTION
  Closes the request. With --comment, leaves that comment first.

ARGUMENTS
  <id>               Request number; default: the open request of the current branch

FLAGS
  --comment <text>   Comment to leave before closing
  --delete-branch    Also delete the source branch on the remote

OUTPUT
  Text: the URL of the request.
  JSON: the closed request, as forge request view --json.

EXAMPLES
  forge request close 42 --comment "Superseded by #43"
EOF
}

cmd_request_close() {
    arg_id='' opt_comment='' opt_delete_branch=''
    while [ $# -gt 0 ]; do
        case $1 in
            -c | --comment) forge_arg "$@"; opt_comment=$2; shift 2 ;;
            -d | --delete-branch) opt_delete_branch=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_call request_close "$arg_id"
    request_report "$arg_id"
}

help_request_reopen() {
    cat <<'EOF'
NAME
  forge request reopen - reopen a closed request

USAGE
  forge request reopen <id>

DESCRIPTION
  Reopens a request that was closed without being merged.

ARGUMENTS
  <id>   Request number

OUTPUT
  Text: the URL of the request.
  JSON: the reopened request, as forge request view --json.

EXAMPLES
  forge request reopen 42
EOF
}

cmd_request_reopen() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$arg_id" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$arg_id"
    forge_call request_reopen "$arg_id"
    request_report "$arg_id"
}

# --- merge -------------------------------------------------------------------------------

help_request_merge() {
    cat <<'EOF'
NAME
  forge request merge - merge a request

USAGE
  forge request merge [<id>] (--squash | --merge | --rebase) [--delete-branch]
                      [--sha <commit>] [--message <text>] [--auto]

DESCRIPTION
  Merges the request now, or with --auto once its checks pass. The strategy has no default:
  which one a project uses is its own rule, so it must be stated.

ARGUMENTS
  <id>               Request number; default: the open request of the current branch

FLAGS
  --squash           Squash all commits into one
  --merge            Create a merge commit
  --rebase           Rebase the commits onto the target (GitHub only)
  --delete-branch    Delete the source branch after merging
  --sha <commit>     Merge only if the head is still this commit
  --message <text>   Commit message of the squash or merge commit; the first line is the
                     subject, the rest after a blank line the body
  --auto             Merge automatically once required checks pass

OUTPUT
  Text and JSON: {state, sha, auto_merge}
  state is merged, or open when --auto queued the merge; sha is the merge commit.

PLATFORM NOTES
  GitLab: --rebase exits 3; rebase is a project merge method there, not a per-merge choice.
  GitLab: without --auto the merge is immediate; a request that is not merged afterwards is
          an error (exit 1), with the host's detailed merge status on stderr.

EXAMPLES
  forge request merge 42 --squash --delete-branch
  forge request merge --squash --sha "$(git rev-parse HEAD)" --message "feat: login (#42)"
  forge request merge 42 --merge --auto
EOF
}

cmd_request_merge() {
    arg_id='' opt_strategy='' opt_delete_branch='' opt_sha='' opt_message='' opt_auto=''
    while [ $# -gt 0 ]; do
        case $1 in
            --squash | --merge | --rebase)
                [ -z "$opt_strategy" ] || forge_usage_die "pick one strategy: --$opt_strategy and $1 were both given"
                opt_strategy=${1#--}
                shift
                ;;
            -d | --delete-branch) opt_delete_branch=1; shift ;;
            --sha) forge_arg "$@"; opt_sha=$2; shift 2 ;;
            -m | --message) forge_arg "$@"; opt_message=$2; shift 2 ;;
            --auto) opt_auto=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$opt_strategy" ] || forge_usage_die "a strategy is required: --squash, --merge or --rebase"
    arg_id=$(request_resolve_id "$arg_id")
    FORGE_JSON=1
    forge_call request_merge "$arg_id"
}

# --- ready -------------------------------------------------------------------------------

help_request_ready() {
    cat <<'EOF'
NAME
  forge request ready - mark a draft ready for review

USAGE
  forge request ready [<id>] [--undo]

DESCRIPTION
  Lifts the draft mark, so the request can be merged. With --undo, turns it back into a draft.

ARGUMENTS
  <id>      Request number; default: the open request of the current branch

FLAGS
  --undo    Turn the request back into a draft

OUTPUT
  Text: the URL of the request.
  JSON: the request after the change, as forge request view --json.

PLATFORM NOTES
  GitLab: lifting the draft mark does not start a pipeline by itself; use 'forge ci run trigger'
          if the project runs pipelines only for ready requests.

EXAMPLES
  forge request ready 42
  forge request ready --undo
EOF
}

cmd_request_ready() {
    arg_id='' opt_undo=''
    while [ $# -gt 0 ]; do
        case $1 in
            --undo) opt_undo=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_call request_ready "$arg_id"
    request_report "$arg_id"
}

# --- checkout / diff / approve -----------------------------------------------------------

help_request_checkout() {
    cat <<'EOF'
NAME
  forge request checkout - check a request out locally

USAGE
  forge request checkout <id> [--branch <name>]

DESCRIPTION
  Fetches the request's head and switches to a local branch tracking it.

ARGUMENTS
  <id>              Request number

FLAGS
  --branch <name>   Local branch name; default: the source branch name

OUTPUT
  Text: the platform CLI's progress. No JSON.

EXAMPLES
  forge request checkout 42
  forge request checkout 42 --branch review/42
EOF
}

cmd_request_checkout() {
    arg_id='' opt_branch=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --branch) forge_arg "$@"; opt_branch=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$arg_id" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$arg_id"
    forge_call request_checkout "$arg_id"
}

help_request_diff() {
    cat <<'EOF'
NAME
  forge request diff - show the changes of a request

USAGE
  forge request diff [<id>] [--name-only]

DESCRIPTION
  Prints the unified diff of the request against its target branch.

ARGUMENTS
  <id>          Request number; default: the open request of the current branch

FLAGS
  --name-only   Only the paths of changed files

OUTPUT
  Text: the diff, or one path per line with --name-only.
  JSON (with --name-only): array of paths.

EXAMPLES
  forge request diff 42
  forge request diff --name-only --json
EOF
}

cmd_request_diff() {
    arg_id='' opt_name_only=''
    while [ $# -gt 0 ]; do
        case $1 in
            --name-only) opt_name_only=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    if forge_json_mode && [ -z "$opt_name_only" ]; then
        forge_usage_die "--json needs --name-only: a diff has no JSON form"
    fi
    forge_call request_diff "$arg_id"
}

help_request_approve() {
    cat <<'EOF'
NAME
  forge request approve - approve a request

USAGE
  forge request approve [<id>] [--body <text> | --body-file <path|->] [--sha <commit>]

DESCRIPTION
  Approves the request as the authenticated user, optionally with a comment.

ARGUMENTS
  <id>                   Request number; default: the open request of the current branch

FLAGS
  --body <text>          Comment to go with the approval
  --body-file <path|->   The comment from a file, or - for stdin
  --sha <commit>         Approve only if the head is still this commit (GitLab)

OUTPUT
  Text: the URL of the request.
  JSON: the request after approval, as forge request view --json.

PLATFORM NOTES
  GitHub: you cannot approve your own pull request.
  GitHub: --sha is ignored; GitHub approves the current head.

EXAMPLES
  forge request approve 42
  forge request approve 42 --body "Looks good"
EOF
}

cmd_request_approve() {
    arg_id='' opt_sha=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            --sha) forge_arg "$@"; opt_sha=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_call request_approve "$arg_id"
    request_report "$arg_id"
}

# --- checks ------------------------------------------------------------------------------

help_request_checks() {
    cat <<'EOF'
NAME
  forge request checks - CI status of a request

USAGE
  forge request checks [<id>] [--watch [--interval <s>]]
  forge request checks [<id>] --log <job>
  forge request checks [<id>] --artifacts <job> [--dir <path>]

DESCRIPTION
  Reports the CI run of the request's head commit: one overall status and one entry per job.
  With --log prints one job's log; with --artifacts downloads one job's artifacts.
  With --watch waits until nothing is pending or running, then reports.

ARGUMENTS
  <id>               Request number; default: the open request of the current branch

FLAGS
  --watch            Poll until the run is finished; exit 1 if it did not succeed
  --interval <s>     Seconds between polls with --watch (default 15)
  --log <job>        Print the log of the job with this name
  --artifacts <job>  Download the artifacts of the job with this name
  --dir <path>       Where artifacts go (default .tmp/ci-artifacts/<job>)

OUTPUT
  Text and JSON: {status, sha, url, jobs: [{stage, name, status, allow_failure, url,
                  started_at, finished_at}]}
  status is success, failed, running, pending, manual, canceled, skipped, or none when no
  CI ran. --log prints raw text; --artifacts prints the directory.

PLATFORM NOTES
  GitHub: there is no single run, so status is aggregated: failed beats pending beats success.
          stage is the workflow name; allow_failure is null. --log and --artifacts work only
          for GitHub Actions checks; artifacts are those of the whole workflow run, unpacked.
  GitLab: the run is the request's head pipeline. Artifacts arrive as <job>.zip.

EXAMPLES
  forge request checks 42
  forge request checks --watch --jq .status
  forge request checks 42 --log test
  forge request checks 42 --artifacts build --dir .tmp/build
EOF
}

cmd_request_checks() {
    arg_id='' opt_watch='' opt_interval=15 opt_log='' opt_artifacts='' opt_dir=''
    while [ $# -gt 0 ]; do
        case $1 in
            --watch) opt_watch=1; shift ;;
            --interval) forge_arg "$@"; opt_interval=$2; shift 2 ;;
            --log) forge_arg "$@"; opt_log=$2; shift 2 ;;
            --artifacts) forge_arg "$@"; opt_artifacts=$2; shift 2 ;;
            --dir) forge_arg "$@"; opt_dir=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -z "$opt_log" ] || [ -z "$opt_artifacts" ] || forge_usage_die "--log and --artifacts cannot be combined"
    [ -z "$opt_dir" ] || [ -n "$opt_artifacts" ] || forge_usage_die "--dir needs --artifacts"
    forge_require_int --interval "$opt_interval"
    arg_id=$(request_resolve_id "$arg_id")

    if [ -n "$opt_log" ]; then
        forge_call request_checks_log "$arg_id" "$opt_log"
        return
    fi
    if [ -n "$opt_artifacts" ]; then
        opt_dir=${opt_dir:-.tmp/ci-artifacts/$opt_artifacts}
        mkdir -p "$opt_dir"
        forge_call request_checks_artifacts "$arg_id" "$opt_artifacts" "$opt_dir"
        printf '%s\n' "$opt_dir"
        return
    fi

    request_checks_user_jq=$FORGE_JQ
    FORGE_JQ=
    while :; do
        request_checks_doc=$(forge_call request_checks "$arg_id") || exit $?
        request_checks_status=$(printf '%s\n' "$request_checks_doc" | _jq -r '.status')
        [ -n "$opt_watch" ] || break
        case $request_checks_status in
            pending | running) sleep "$opt_interval" ;;
            *) break ;;
        esac
    done
    FORGE_JQ=$request_checks_user_jq
    forge_emit_doc "$request_checks_doc" '.'
    if [ -n "$opt_watch" ]; then
        case $request_checks_status in
            success | skipped | none) ;;
            *) exit 1 ;;
        esac
    fi
}

# --- id / url / ref / fetch / template ---------------------------------------------------

help_request_id() {
    cat <<'EOF'
NAME
  forge request id - number of the request for a branch

USAGE
  forge request id [<branch>] [--state <state>]

DESCRIPTION
  Finds the request whose source branch is <branch>. Exits 4 when there is none.

ARGUMENTS
  <branch>          Source branch; default: the current branch

FLAGS
  --state <state>   open (default), closed, merged or all; the newest match wins

OUTPUT
  Text: the number.
  JSON: {"id": 42}

EXAMPLES
  forge request id
  forge request id feature/login --state all
EOF
}

cmd_request_id() {
    arg_branch='' opt_state=open
    while [ $# -gt 0 ]; do
        case $1 in
            --state) forge_arg "$@"; opt_state=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_branch" ] || forge_unexpected "$1"; arg_branch=$1; shift ;;
        esac
    done
    forge_require_one_of --state "$opt_state" open closed merged all
    if [ -z "$arg_branch" ]; then
        arg_branch=$(forge_current_branch)
        [ -n "$arg_branch" ] || forge_usage_die "HEAD is detached: pass the <branch>"
    fi
    request_id_found=$(forge_call request_find "$arg_branch" "$opt_state") || exit $?
    [ -n "$request_id_found" ] || forge_not_found "no $opt_state request for branch '$arg_branch'"
    if forge_json_mode; then
        _jq -n --argjson id "$request_id_found" '{id: $id}' | forge_emit '.'
    else
        printf '%s\n' "$request_id_found"
    fi
}

help_request_url() {
    cat <<'EOF'
NAME
  forge request url - web address of a request

USAGE
  forge request url [<id>]

DESCRIPTION
  Prints the browser URL of the request.

ARGUMENTS
  <id>   Request number; default: the open request of the current branch

OUTPUT
  Text: the URL.
  JSON: {"url": "..."}

EXAMPLES
  forge request url 42
EOF
}

cmd_request_url() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    if forge_json_mode; then
        request_url_value=$(FORGE_JSON='' forge_call request_url "$arg_id") || exit $?
        _jq -n --arg url "$request_url_value" '{url: $url}' | forge_emit '.'
    else
        forge_call request_url "$arg_id"
    fi
}

help_request_ref() {
    cat <<'EOF'
NAME
  forge request ref - how a commit message names a request

USAGE
  forge request ref [<id>]

DESCRIPTION
  Prints the request reference in the platform's notation, for commit subjects and comments.

ARGUMENTS
  <id>   Request number; default: the open request of the current branch

OUTPUT
  Text: #42 on GitHub, !42 on GitLab.
  JSON: {"ref": "#42"}

EXAMPLES
  forge request ref 42
  git commit -m "feat: login ($(forge request ref))"
EOF
}

cmd_request_ref() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    forge_resolve_repo
    case $FORGE_PLATFORM in
        github) request_ref_value="#$arg_id" ;;
        gitlab) request_ref_value="!$arg_id" ;;
    esac
    if forge_json_mode; then
        _jq -n --arg ref "$request_ref_value" '{ref: $ref}' | forge_emit '.'
    else
        printf '%s\n' "$request_ref_value"
    fi
}

help_request_fetch() {
    cat <<'EOF'
NAME
  forge request fetch - fetch a request's head into a local ref

USAGE
  forge request fetch <id>

DESCRIPTION
  Fetches the head of the request, including requests from forks, into
  refs/remotes/<remote>/request/<id>, without touching the working tree.
  With --repo, it fetches from that repository by URL into
  refs/forge/<host>/<path>/request/<id>.

ARGUMENTS
  <id>   Request number

OUTPUT
  Text: the local ref.
  JSON: {"ref": "refs/remotes/origin/request/42", "sha": "..."}

EXAMPLES
  forge request fetch 42
  git diff main...$(forge request fetch 42)
EOF
}

cmd_request_fetch() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$arg_id" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$arg_id"
    forge_resolve_repo
    case $FORGE_PLATFORM in
        github) request_fetch_src="refs/pull/$arg_id/head" ;;
        gitlab) request_fetch_src="refs/merge-requests/$arg_id/head" ;;
    esac
    request_fetch_remote=$(forge_remote_name)
    request_fetch_ref="refs/remotes/$request_fetch_remote/request/$arg_id"
    # --repo names another repository: fetch from it by URL, into a ref that cannot be confused
    # with the local remote's requests.
    if [ -n "$FORGE_REPO_FLAG" ]; then
        request_fetch_remote="https://$FORGE_HOST/$FORGE_REPO_PATH.git"
        request_fetch_ref="refs/forge/$(printf %s "$FORGE_HOST" | tr : _)/$FORGE_REPO_PATH/request/$arg_id"
    fi
    git fetch -q "$request_fetch_remote" "+$request_fetch_src:$request_fetch_ref" ||
        forge_die "cannot fetch $request_fetch_src from $request_fetch_remote"
    if forge_json_mode; then
        _jq -n --arg ref "$request_fetch_ref" --arg sha "$(git rev-parse "$request_fetch_ref")" \
            '{ref: $ref, sha: $sha}' | forge_emit '.'
    else
        printf '%s\n' "$request_fetch_ref"
    fi
}

help_request_template() {
    cat <<'EOF'
NAME
  forge request template - path of the request description template

USAGE
  forge request template

DESCRIPTION
  Prints where this platform looks for the default request description template, and whether
  the repository has one. Checks the usual locations in order.

OUTPUT
  Text: the path of the existing template, or the conventional path when none exists.
  JSON: {"path": "...", "exists": true}

PLATFORM NOTES
  GitHub: .github/pull_request_template.md, PULL_REQUEST_TEMPLATE.md, docs/..., root.
  GitLab: .gitlab/merge_request_templates/Default.md.

EXAMPLES
  forge request template
  cat "$(forge request template)"
EOF
}

cmd_request_template() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_resolve_repo
    case $FORGE_PLATFORM in
        github) request_template_candidates='.github/pull_request_template.md
.github/PULL_REQUEST_TEMPLATE.md
docs/pull_request_template.md
docs/PULL_REQUEST_TEMPLATE.md
pull_request_template.md
PULL_REQUEST_TEMPLATE.md' ;;
        gitlab) request_template_candidates='.gitlab/merge_request_templates/Default.md
.gitlab/merge_request_templates/default.md' ;;
    esac
    request_template_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    request_template_path=''
    request_template_exists=false
    while IFS= read -r request_template_candidate; do
        if [ -f "$request_template_root/$request_template_candidate" ]; then
            request_template_path=$request_template_candidate
            request_template_exists=true
            break
        fi
    done <<EOF
$request_template_candidates
EOF
    [ -n "$request_template_path" ] || request_template_path=$(printf '%s\n' "$request_template_candidates" | sed -n 1p)
    if forge_json_mode; then
        forge_require jq
        _jq -n --arg p "$request_template_path" --argjson e "$request_template_exists" \
            '{path: $p, exists: $e}' | forge_emit '.'
    else
        printf '%s\n' "$request_template_path"
    fi
}

# --- comment -----------------------------------------------------------------------------

help_request_comment() {
    cat <<'EOF'
forge request comment - comments on a request

COMMANDS
  list     Comments on the request as a whole
  add      Comment on the request as a whole
  edit     Replace the text of a comment
  inline   Comment on one line of the diff

Run 'forge request comment <command> --help' for details.
EOF
}

help_request_comment_list() {
    cat <<'EOF'
NAME
  forge request comment list - comments on a request

USAGE
  forge request comment list [<id>]

DESCRIPTION
  Lists comments on the request as a whole, without system notes and without
  inline review comments (see 'forge request thread list').

ARGUMENTS
  <id>   Request number; default: the open request of the current branch

OUTPUT
  Text: one block per comment: id, author, date, body.
  JSON: array of {id, author, body, created_at, updated_at, url}

PLATFORM NOTES
  Order is not normalised: do not rely on position, pick by content or created_at.

EXAMPLES
  forge request comment list 42 --json
  forge request comment list --jq '.[] | select(.author == "ci-bot") | .id'
EOF
}

cmd_request_comment_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    request_comments_doc=$(FORGE_JQ='' forge_call request_comment_list "$arg_id") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$request_comments_doc" '.'
    else
        forge_emit_doc "$request_comments_doc" \
            '.[] | "#\(.id)  \(.author)  \(.created_at)\n\(.body)\n"' -r
    fi
}

help_request_comment_add() {
    cat <<'EOF'
NAME
  forge request comment add - comment on a request

USAGE
  forge request comment add [<id>] (--body <text> | --body-file <path|->)

DESCRIPTION
  Adds a comment to the request as a whole.

ARGUMENTS
  <id>                   Request number; default: the open request of the current branch

FLAGS
  --body <text>          Comment text (Markdown)
  --body-file <path|->   Comment text from a file, or - for stdin

OUTPUT
  Text: the comment id.
  JSON: {id, author, body, created_at, updated_at, url}

EXAMPLES
  forge request comment add 42 --body "Rebased onto main"
  forge request comment add --body-file .tmp/review.md --jq .id
EOF
}

cmd_request_comment_add() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    forge_require_body "the comment"
    arg_id=$(request_resolve_id "$arg_id")
    request_comment_doc=$(FORGE_JQ='' forge_call request_comment_add "$arg_id") || exit $?
    request_comment_print "$request_comment_doc"
}

request_comment_print() {
    if forge_json_mode; then
        forge_emit_doc "$1" '.'
    else
        forge_emit_doc "$1" '.id' -r
    fi
}

help_request_comment_edit() {
    cat <<'EOF'
NAME
  forge request comment edit - replace the text of a comment

USAGE
  forge request comment edit <id> <comment-id> (--body <text> | --body-file <path|->)

DESCRIPTION
  Replaces the whole text of one comment on the request. Works for comments listed by
  'comment list' and, on GitLab, for notes inside threads.

ARGUMENTS
  <id>                   Request number
  <comment-id>           Comment id from 'forge request comment list'

FLAGS
  --body <text>          New text
  --body-file <path|->   New text from a file, or - for stdin

OUTPUT
  Text: the comment id.
  JSON: {id, author, body, created_at, updated_at, url}

EXAMPLES
  forge request comment edit 42 123456 --body "Updated: all checks pass"
EOF
}

cmd_request_comment_edit() {
    arg_id='' arg_comment=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                elif [ -z "$arg_comment" ]; then arg_comment=$1
                else forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_comment" ] || forge_usage_die "<id> and <comment-id> are required"
    forge_require_int "<id>" "$arg_id"
    forge_require_int "<comment-id>" "$arg_comment"
    forge_require_body "the comment"
    request_comment_doc=$(FORGE_JQ='' forge_call request_comment_edit "$arg_id" "$arg_comment") || exit $?
    request_comment_print "$request_comment_doc"
}

help_request_comment_inline() {
    cat <<'EOF'
NAME
  forge request comment inline - comment on one line of the diff

USAGE
  forge request comment inline <id> <path> <line> (--body <text> | --body-file <path|->)

DESCRIPTION
  Starts a review thread on one line of the new version of a file, pinned to the request's
  current head. The answer is checked: a comment the host did not anchor is an error.

ARGUMENTS
  <id>                   Request number
  <path>                 File path relative to the repository root
  <line>                 Line number in the new version of the file

FLAGS
  --body <text>          Comment text (Markdown; may contain a suggestion fence)
  --body-file <path|->   Comment text from a file, or - for stdin

OUTPUT
  Text: the thread id.
  JSON: {thread_id, comment_id, path, line, url}

PLATFORM NOTES
  <line> must be an added or changed line. GitLab also anchors unchanged context lines only
  with the old line number, which this command does not send: it fails there.

EXAMPLES
  forge request comment inline 42 src/app.sh 17 --body "Quote this variable"
  forge request comment inline 42 lib/x.sh 3 --body-file .tmp/finding.md --jq .thread_id
EOF
}

cmd_request_comment_inline() {
    arg_id='' arg_path='' arg_line=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                elif [ -z "$arg_path" ]; then arg_path=$1
                elif [ -z "$arg_line" ]; then arg_line=$1
                else forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_line" ] || forge_usage_die "<id> <path> <line> are required"
    forge_require_int "<id>" "$arg_id"
    forge_require_int "<line>" "$arg_line"
    forge_require_body "the comment"
    request_inline_doc=$(FORGE_JQ='' forge_call request_comment_inline "$arg_id" "$arg_path" "$arg_line") || exit $?
    if forge_json_mode; then
        forge_emit_doc "$request_inline_doc" '.'
    else
        forge_emit_doc "$request_inline_doc" '.thread_id' -r
    fi
}

# --- thread ------------------------------------------------------------------------------

help_request_thread() {
    cat <<'EOF'
forge request thread - review threads of a request

COMMANDS
  list        Threads with their state
  reply       Reply inside a thread
  resolve     Mark a thread resolved
  unresolve   Mark a thread unresolved

Run 'forge request thread <command> --help' for details.
EOF
}

help_request_thread_list() {
    cat <<'EOF'
NAME
  forge request thread list - review threads of a request

USAGE
  forge request thread list [<id>] [--unresolved]

DESCRIPTION
  Lists resolvable discussion threads: the first comment, the last reply, and whether the
  thread is resolved.

ARGUMENTS
  <id>           Request number; default: the open request of the current branch

FLAGS
  --unresolved   Only threads that are not resolved

OUTPUT
  Text: one block per thread.
  JSON: array of {thread_id, resolved, path, line, author, body, last_author, last_body}
        path and line are null for a thread not tied to a diff line.

PLATFORM NOTES
  GitHub: only inline review threads exist; plain comments are not threads.
  GitLab: any resolvable discussion, inline or not; system notes are left out.

EXAMPLES
  forge request thread list 42 --unresolved --json
  forge request thread list --jq 'map(select(.resolved | not)) | length'
EOF
}

cmd_request_thread_list() {
    arg_id='' opt_unresolved=''
    while [ $# -gt 0 ]; do
        case $1 in
            --unresolved) opt_unresolved=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    request_threads_doc=$(FORGE_JQ='' forge_call request_thread_list "$arg_id") || exit $?
    if [ -n "$opt_unresolved" ]; then
        request_threads_doc=$(printf '%s\n' "$request_threads_doc" | _jq '[.[] | select(.resolved | not)]')
    fi
    if forge_json_mode; then
        forge_emit_doc "$request_threads_doc" '.'
    else
        forge_emit_doc "$request_threads_doc" '.[] |
            "\(.thread_id)  \(if .resolved then "resolved" else "open" end)  \(.path // "-"):\(.line // "-")\n  \(.author): \(.body | split("\n")[0])\n  last \(.last_author): \(.last_body | split("\n")[0])\n"' -r
    fi
}

help_request_thread_reply() {
    cat <<'EOF'
NAME
  forge request thread reply - reply inside a review thread

USAGE
  forge request thread reply <id> <thread-id> (--body <text> | --body-file <path|->)

DESCRIPTION
  Adds a reply to an existing thread, as opposed to a new top-level comment.

ARGUMENTS
  <id>                   Request number
  <thread-id>            Thread id from 'forge request thread list'

FLAGS
  --body <text>          Reply text
  --body-file <path|->   Reply text from a file, or - for stdin

OUTPUT
  Text: the id of the new reply.
  JSON: {id, thread_id, author, body}

EXAMPLES
  forge request thread reply 42 PRRT_kwDOabc --body "Fixed in 1a2b3c4"
EOF
}

cmd_request_thread_reply() {
    arg_id='' arg_thread=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                elif [ -z "$arg_thread" ]; then arg_thread=$1
                else forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_thread" ] || forge_usage_die "<id> and <thread-id> are required"
    forge_require_int "<id>" "$arg_id"
    forge_require_body "the reply"
    request_reply_doc=$(FORGE_JQ='' forge_call request_thread_reply "$arg_id" "$arg_thread") || exit $?
    request_comment_print "$request_reply_doc"
}

help_request_thread_resolve() {
    cat <<'EOF'
NAME
  forge request thread resolve - mark a review thread resolved

USAGE
  forge request thread resolve <id> <thread-id>

DESCRIPTION
  Marks the thread resolved, like the "Resolve" button.

ARGUMENTS
  <id>          Request number
  <thread-id>   Thread id from 'forge request thread list'

OUTPUT
  Text: the thread id.
  JSON: {thread_id, resolved}

EXAMPLES
  forge request thread resolve 42 PRRT_kwDOabc
EOF
}

request_thread_state() {
    arg_id='' arg_thread=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                elif [ -z "$arg_thread" ]; then arg_thread=$1
                else forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_thread" ] || forge_usage_die "<id> and <thread-id> are required"
    forge_require_int "<id>" "$arg_id"
}

cmd_request_thread_resolve() {
    request_thread_state "$@"
    forge_call request_thread_set "$arg_id" "$arg_thread" true
    request_thread_print true
}

request_thread_print() {
    if forge_json_mode; then
        _jq -n --arg t "$arg_thread" --argjson r "$1" '{thread_id: $t, resolved: $r}' | forge_emit '.'
    else
        printf '%s\n' "$arg_thread"
    fi
}

help_request_thread_unresolve() {
    cat <<'EOF'
NAME
  forge request thread unresolve - mark a review thread unresolved

USAGE
  forge request thread unresolve <id> <thread-id>

DESCRIPTION
  Reopens a resolved thread.

ARGUMENTS
  <id>          Request number
  <thread-id>   Thread id from 'forge request thread list'

OUTPUT
  Text: the thread id.
  JSON: {thread_id, resolved}

EXAMPLES
  forge request thread unresolve 42 PRRT_kwDOabc
EOF
}

cmd_request_thread_unresolve() {
    request_thread_state "$@"
    forge_call request_thread_set "$arg_id" "$arg_thread" false
    request_thread_print false
}

# --- label / reviewer --------------------------------------------------------------------

help_request_label() {
    cat <<'EOF'
forge request label - labels of a request

COMMANDS
  list     Labels on the request
  add      Add labels
  remove   Remove labels

Run 'forge request label <command> --help' for details.
EOF
}

help_request_label_list() {
    cat <<'EOF'
NAME
  forge request label list - labels on a request

USAGE
  forge request label list [<id>]

DESCRIPTION
  Prints the labels of the request.

ARGUMENTS
  <id>   Request number; default: the open request of the current branch

OUTPUT
  Text: one label per line.
  JSON: array of label names.

EXAMPLES
  forge request label list 42
EOF
}

cmd_request_label_list() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    arg_id=$(request_resolve_id "$arg_id")
    request_labels_user_jq=$FORGE_JQ
    request_labels_doc=$(FORGE_JQ='' FORGE_JSON=1 forge_call request_view "$arg_id") || exit $?
    FORGE_JQ=$request_labels_user_jq
    if forge_json_mode; then
        forge_emit_doc "$request_labels_doc" '.labels'
    else
        forge_emit_doc "$request_labels_doc" '.labels[]' -r
    fi
}

help_request_label_add() {
    cat <<'EOF'
NAME
  forge request label add - add labels to a request

USAGE
  forge request label add <id> <label>...

DESCRIPTION
  Adds the labels. A label that does not exist in the repository yet is created.

ARGUMENTS
  <id>      Request number
  <label>   Label name; give several to add several

OUTPUT
  Text: the labels of the request afterwards, one per line.
  JSON: array of label names.

EXAMPLES
  forge request label add 42 bug needs-review
EOF
}

request_label_args() {
    arg_id='' arg_values=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_id" ]; then arg_id=$1
                else arg_values=$(forge_list_add "$arg_values" "$1")
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_values" ] || forge_usage_die "<id> and at least one value are required"
    forge_require_int "<id>" "$arg_id"
}

cmd_request_label_add() {
    request_label_args "$@"
    forge_call request_label_add "$arg_id" "$arg_values"
    cmd_request_label_list "$arg_id"
}

help_request_label_remove() {
    cat <<'EOF'
NAME
  forge request label remove - remove labels from a request

USAGE
  forge request label remove <id> <label>...

DESCRIPTION
  Removes the labels. A label the request does not carry is ignored.

ARGUMENTS
  <id>      Request number
  <label>   Label name; give several to remove several

OUTPUT
  Text: the labels of the request afterwards, one per line.
  JSON: array of label names.

EXAMPLES
  forge request label remove 42 wip
EOF
}

cmd_request_label_remove() {
    request_label_args "$@"
    forge_call request_label_remove "$arg_id" "$arg_values"
    cmd_request_label_list "$arg_id"
}

help_request_reviewer() {
    cat <<'EOF'
forge request reviewer - reviewers of a request

COMMANDS
  add      Ask users for review
  remove   Withdraw review requests

Run 'forge request reviewer <command> --help' for details.
EOF
}

help_request_reviewer_add() {
    cat <<'EOF'
NAME
  forge request reviewer add - ask users to review a request

USAGE
  forge request reviewer add <id> <user>...

DESCRIPTION
  Requests a review from each user.

ARGUMENTS
  <id>     Request number
  <user>   Username; give several to ask several

OUTPUT
  Text: the reviewers afterwards, one per line.
  JSON: array of usernames.

EXAMPLES
  forge request reviewer add 42 alice bob
EOF
}

cmd_request_reviewer_add() {
    request_label_args "$@"
    opt_add_reviewers=$arg_values opt_remove_reviewers=''
    request_reviewer_apply
}

request_reviewer_apply() {
    opt_title='' opt_target='' opt_milestone='' opt_add_labels='' opt_remove_labels=''
    opt_add_assignees='' opt_remove_assignees=''
    FORGE_BODY_SET=
    forge_call request_edit "$arg_id"
    request_reviewers_user_jq=$FORGE_JQ
    request_reviewers_doc=$(FORGE_JQ='' FORGE_JSON=1 forge_call request_view "$arg_id") || exit $?
    FORGE_JQ=$request_reviewers_user_jq
    if forge_json_mode; then
        forge_emit_doc "$request_reviewers_doc" '.reviewers'
    else
        forge_emit_doc "$request_reviewers_doc" '.reviewers[]' -r
    fi
}

help_request_reviewer_remove() {
    cat <<'EOF'
NAME
  forge request reviewer remove - withdraw review requests

USAGE
  forge request reviewer remove <id> <user>...

DESCRIPTION
  Removes each user from the requested reviewers.

ARGUMENTS
  <id>     Request number
  <user>   Username; give several to remove several

OUTPUT
  Text: the reviewers afterwards, one per line.
  JSON: array of usernames.

EXAMPLES
  forge request reviewer remove 42 bob
EOF
}

cmd_request_reviewer_remove() {
    request_label_args "$@"
    opt_add_reviewers='' opt_remove_reviewers=$arg_values
    request_reviewer_apply
}

# --- suggestion --------------------------------------------------------------------------

help_request_suggestion() {
    cat <<'EOF'
forge request suggestion - suggested changes in review comments

COMMANDS
  fence   Opening fence of a suggestion block

Run 'forge request suggestion fence --help' for details.
EOF
}

help_request_suggestion_fence() {
    cat <<'EOF'
NAME
  forge request suggestion fence - opening fence of a suggestion block

USAGE
  forge request suggestion fence [<before> <after>]

DESCRIPTION
  Prints the line that opens a suggested change, which the author can apply from the web UI.
  Put the replacement lines after it and close with ```. Use it inside an inline comment.

ARGUMENTS
  <before>   Extra lines above the commented line that the suggestion replaces (default 0)
  <after>    Extra lines below it (default 0)

OUTPUT
  Text: the fence, e.g. ```suggestion or ```suggestion:-0+2
  JSON: {"fence": "..."}

PLATFORM NOTES
  GitHub: only single-line suggestions can be expressed this way; non-zero <before> or
          <after> exits 3.

EXAMPLES
  forge request suggestion fence
  forge request suggestion fence 0 2
EOF
}

cmd_request_suggestion_fence() {
    arg_before='' arg_after=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_before" ]; then arg_before=$1
                elif [ -z "$arg_after" ]; then arg_after=$1
                else forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    arg_before=${arg_before:-0}
    arg_after=${arg_after:-0}
    forge_require_int "<before>" "$arg_before"
    forge_require_int "<after>" "$arg_after"
    forge_resolve_repo
    case $FORGE_PLATFORM in
        github)
            [ "$arg_before" = 0 ] && [ "$arg_after" = 0 ] ||
                forge_unsupported "a multi-line suggestion from a single-line comment"
            request_fence='```suggestion'
            ;;
        gitlab) request_fence="\`\`\`suggestion:-$arg_before+$arg_after" ;;
    esac
    if forge_json_mode; then
        forge_require jq
        _jq -n --arg f "$request_fence" '{fence: $f}' | forge_emit '.'
    else
        printf '%s\n' "$request_fence"
    fi
}
