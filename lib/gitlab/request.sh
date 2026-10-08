# shellcheck shell=sh

GL_REQUEST_DEF='
def gl_state: if . == "opened" then "open" elif . == "locked" then "open" else . end;
def gl_request: {
    id: .iid,
    title,
    state: (.state | gl_state),
    draft: (.draft // .work_in_progress // false),
    author: .author.username,
    source_branch,
    target_branch,
    url: .web_url,
    description,
    labels: (.labels // []),
    assignees: [(.assignees // [])[].username],
    reviewers: [(.reviewers // [])[].username],
    sha,
    created_at,
    updated_at,
    merged_at,
    closed_at,
    mergeable: (
        if ((.merge_status // "") | test("unchecked|checking")) then null
        else (.has_conflicts | not)
        end
    )
};
def gl_note($url): {id, author: .author.username, body, created_at, updated_at,
    url: ($url + "#note_" + (.id | tostring))};
'

gitlab_request_state_param() {
    case $1 in
        open) printf 'opened' ;;
        *) printf '%s' "$1" ;;
    esac
}

gitlab_request_url_of() {
    printf '%s/-/merge_requests/%s' "$(gitlab_web_url)" "$1"
}

# GET a list endpoint with at most $2 items, following pages past 100.
gitlab_api_limit() {
    if [ "$2" -le 100 ]; then
        forge_capture gitlab_api "$1&per_page=$2"
    else
        gl_limit_doc=$(forge_capture gitlab_api_all "$1&per_page=100") || return $?
        printf '%s\n' "$gl_limit_doc" | _jq --argjson n "$2" '.[:$n]'
    fi
}



gitlab_request_list() {
    if ! forge_json_mode; then
        set -- mr list -R "$FORGE_R" --per-page "$opt_limit"
        case $opt_state in
            closed) set -- "$@" --closed ;;
            merged) set -- "$@" --merged ;;
            all) set -- "$@" --all ;;
        esac
        [ -z "$opt_author" ] || set -- "$@" --author "$(gitlab_user "$opt_author")"
        [ -z "$opt_assignee" ] || set -- "$@" --assignee "$(gitlab_user "$opt_assignee")"
        [ -z "$opt_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_labels")"
        [ -z "$opt_source" ] || set -- "$@" --source-branch "$opt_source"
        [ -z "$opt_target" ] || set -- "$@" --target-branch "$opt_target"
        [ -z "$opt_draft" ] || set -- "$@" --draft
        [ -z "$opt_search" ] || set -- "$@" --search "$opt_search"
        forge_capture glab "$@"
        return
    fi
    gl_q="$FORGE_API/merge_requests?order_by=created_at&sort=desc&state=$(gitlab_request_state_param "$opt_state")"
    [ -z "$opt_author" ] || gl_q="$gl_q&author_username=$(forge_urlencode "$(gitlab_user "$opt_author")")"
    [ -z "$opt_assignee" ] || gl_q="$gl_q&assignee_username=$(forge_urlencode "$(gitlab_user "$opt_assignee")")"
    [ -z "$opt_labels" ] || gl_q="$gl_q&labels=$(forge_urlencode "$(forge_list_csv "$opt_labels")")"
    [ -z "$opt_source" ] || gl_q="$gl_q&source_branch=$(forge_urlencode "$opt_source")"
    [ -z "$opt_target" ] || gl_q="$gl_q&target_branch=$(forge_urlencode "$opt_target")"
    [ -z "$opt_draft" ] || gl_q="$gl_q&wip=yes"
    [ -z "$opt_search" ] || gl_q="$gl_q&search=$(forge_urlencode "$opt_search")"
    gl_list=$(gitlab_api_limit "$gl_q" "$opt_limit") || return $?
    forge_emit_doc "$gl_list" "$GL_REQUEST_DEF [.[] | gl_request]"
}

gitlab_request_view() {
    if ! forge_json_mode; then
        set -- mr view "$1" -R "$FORGE_R"
        [ -z "${opt_comments:-}" ] || set -- "$@" --comments
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture glab "$@"
        return
    fi
    gl_mr=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1") || return $?
    # approval_state and approval_rules need Premium; /approvals works everywhere.
    gl_approvals=$(gitlab_api "$FORGE_API/merge_requests/$1/approvals" 2>/dev/null) || gl_approvals='{}'
    forge_emit_doc "$gl_mr" "$GL_REQUEST_DEF gl_request + {
        approved: (\$approvals.approved // false),
        approved_by: [(\$approvals.approved_by // [])[].user.username],
        decision: null
    }" --argjson approvals "$gl_approvals"
}

gitlab_request_find() {
    gl_find=$(forge_capture gitlab_api "$FORGE_API/merge_requests?source_branch=$(forge_urlencode "$1")&state=$(gitlab_request_state_param "$2")&order_by=created_at&sort=desc&per_page=1") ||
        return $?
    printf '%s\n' "$gl_find" | _jq -r '.[0].iid // empty'
}

gitlab_request_url() {
    gl_mr=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1") || return $?
    printf '%s\n' "$gl_mr" | _jq -r '.web_url'
}

gitlab_request_create() {
    # --yes skips prompts: forge runs unattended.
    set -- mr create -R "$FORGE_R" --yes --source-branch "$opt_source"
    if [ -n "$opt_title" ]; then
        set -- "$@" --title "$opt_title" --description "${FORGE_BODY:-}"
    else
        set -- "$@" --fill
    fi
    [ -z "$opt_target" ] || set -- "$@" --target-branch "$opt_target"
    [ -z "$opt_draft" ] || set -- "$@" --draft
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_labels")"
    [ -z "$opt_delete_branch" ] || set -- "$@" --remove-source-branch
    if [ -n "$opt_assignees" ]; then
        gl_people=
        while IFS= read -r gl_item; do
            [ -z "$gl_item" ] || gl_people=$(forge_list_add "$gl_people" "$(gitlab_user "$gl_item")")
        done <<EOF
$opt_assignees
EOF
        set -- "$@" --assignee "$(forge_list_csv "$gl_people")"
    fi
    [ -z "$opt_reviewers" ] || set -- "$@" --reviewer "$(forge_list_csv "$opt_reviewers")"
    gl_create_out=$(forge_capture glab "$@") || return $?
    gl_create_url=$(printf '%s\n' "$gl_create_out" | grep -Eo 'https?://[^[:space:]]+/merge_requests/[0-9]+' | tail -n 1)
    [ -n "$gl_create_url" ] || forge_die "glab did not report the new merge request: $gl_create_out"
    printf '%s' "${gl_create_url##*/}"
}

# glab takes "+user" to add and "-user" to remove, comma-separated.
gitlab_people_delta() {
    gl_delta=
    while IFS= read -r gl_item; do
        [ -z "$gl_item" ] || gl_delta=$(forge_list_add "$gl_delta" "+$(gitlab_user "$gl_item")")
    done <<EOF
$1
EOF
    while IFS= read -r gl_item; do
        [ -z "$gl_item" ] || gl_delta=$(forge_list_add "$gl_delta" "-$(gitlab_user "$gl_item")")
    done <<EOF
$2
EOF
    forge_list_csv "$gl_delta"
}

gitlab_request_edit() {
    set -- mr update "$1" -R "$FORGE_R" --yes
    gl_edit_base=$#
    [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --description "$FORGE_BODY"
    [ -z "$opt_target" ] || set -- "$@" --target-branch "$opt_target"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    [ -z "$opt_add_labels" ] || set -- "$@" --label "$(forge_list_csv "$opt_add_labels")"
    [ -z "$opt_remove_labels" ] || set -- "$@" --unlabel "$(forge_list_csv "$opt_remove_labels")"
    if [ -n "$opt_add_assignees$opt_remove_assignees" ]; then
        set -- "$@" --assignee "$(gitlab_people_delta "$opt_add_assignees" "$opt_remove_assignees")"
    fi
    if [ -n "$opt_add_reviewers$opt_remove_reviewers" ]; then
        set -- "$@" --reviewer "$(gitlab_people_delta "$opt_add_reviewers" "$opt_remove_reviewers")"
    fi
    [ "$#" -gt "$gl_edit_base" ] || return 0
    forge_capture glab "$@" >/dev/null
}

gitlab_request_close() {
    if [ -n "$opt_comment" ]; then
        forge_capture gitlab_api "$FORGE_API/merge_requests/$1/notes" -X POST -f "body=$opt_comment" >/dev/null ||
            return $?
    fi
    gl_close_branch=
    if [ -n "$opt_delete_branch" ]; then
        gl_mr=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1") || return $?
        gl_close_branch=$(printf '%s\n' "$gl_mr" | _jq -r '.source_branch')
    fi
    forge_capture glab mr close "$1" -R "$FORGE_R" >/dev/null || return $?
    if [ -n "$gl_close_branch" ]; then
        forge_capture gitlab_api -X DELETE "$FORGE_API/repository/branches/$(forge_urlencode "$gl_close_branch")" >/dev/null
    fi
}

gitlab_request_reopen() {
    forge_capture glab mr reopen "$1" -R "$FORGE_R" >/dev/null
}

# Merged through the API: glab mr merge defaults to auto-merge, which turns "merge" into
# "merge some day" whenever a pipeline is still running.
gitlab_request_merge() {
    [ "$opt_strategy" != rebase ] ||
        forge_unsupported "--rebase (GitLab sets rebase as the project merge method; use --squash or --merge)"
    gl_payload=$(_jq -n \
        --argjson squash "$([ "$opt_strategy" = squash ] && echo true || echo false)" \
        --argjson remove "$(gitlab_bool "$opt_delete_branch")" \
        --argjson auto "$(gitlab_bool "$opt_auto")" \
        --arg message "$opt_message" --arg sha "$opt_sha" '
        {squash: $squash, should_remove_source_branch: $remove, merge_when_pipeline_succeeds: $auto}
        + (if $message == "" then {} elif $squash then {squash_commit_message: $message}
           else {merge_commit_message: $message} end)
        + (if $sha == "" then {} else {sha: $sha} end)')
    # Nested JSON needs --input; without the Content-Type header GitLab answers 415.
    if ! gl_merged=$(printf '%s\n' "$gl_payload" | forge_capture gitlab_api "$FORGE_API/merge_requests/$1/merge" \
        -X PUT --input - -H "Content-Type: application/json"); then
        gl_why=$(gitlab_api "$FORGE_API/merge_requests/$1" 2>/dev/null | _jq -r '.detailed_merge_status // empty')
        forge_die "GitLab refused to merge !$1${gl_why:+ (merge status: $gl_why)}"
    fi
    gl_state=$(printf '%s\n' "$gl_merged" | _jq -r '.state // empty')
    if [ -z "$opt_auto" ] && [ "$gl_state" != merged ]; then
        forge_die "GitLab accepted the call but !$1 is ${gl_state:-in an unknown state}, not merged"
    fi
    forge_emit_doc "$gl_merged" '{
        state: (if .state == "opened" then "open" else .state end),
        sha: .merge_commit_sha,
        auto_merge: (.merge_when_pipeline_succeeds // false)
    }'
}

gitlab_request_ready() {
    if [ -n "$opt_undo" ]; then
        forge_capture glab mr update "$1" -R "$FORGE_R" --draft --yes >/dev/null
    else
        forge_capture glab mr update "$1" -R "$FORGE_R" --ready --yes >/dev/null
    fi
}

gitlab_request_checkout() {
    set -- mr checkout "$1" -R "$FORGE_R"
    [ -z "$opt_branch" ] || set -- "$@" --branch "$opt_branch"
    forge_capture glab "$@"
}

gitlab_request_diff() {
    if [ -z "$opt_name_only" ]; then
        forge_capture glab mr diff "$1" -R "$FORGE_R" --raw
        return
    fi
    gl_diffs=$(forge_capture gitlab_api_all "$FORGE_API/merge_requests/$1/diffs?per_page=100") || return $?
    if forge_json_mode; then
        forge_emit_doc "$gl_diffs" '[.[].new_path]'
    else
        printf '%s\n' "$gl_diffs" | _jq -r '.[].new_path'
    fi
}

gitlab_request_approve() {
    set -- mr approve "$1" -R "$FORGE_R"
    [ -z "$opt_sha" ] || set -- "$@" --sha "$opt_sha"
    forge_capture glab "$@" >/dev/null || return $?
    if [ -n "${FORGE_BODY_SET:-}" ]; then
        forge_capture gitlab_api "$FORGE_API/merge_requests/$arg_id/notes" -X POST -f "body=$FORGE_BODY" >/dev/null
    fi
}

# --- checks ------------------------------------------------------------------------------

# The run is the request's head pipeline: pinned to its head commit, not the newest on the branch.
gitlab_head_pipeline() {
    gl_mr=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1") || return $?
    gl_pipeline=$(printf '%s\n' "$gl_mr" | _jq -r '.head_pipeline.id // empty')
}

gitlab_request_checks() {
    gitlab_head_pipeline "$1" || return $?
    if [ -z "$gl_pipeline" ]; then
        forge_emit_doc "$gl_mr" '{status: "none", sha, url: null, jobs: []}'
        return
    fi
    gl_jobs=$(forge_capture gitlab_api_all "$FORGE_API/pipelines/$gl_pipeline/jobs?per_page=100") || return $?
    forge_emit_doc "$gl_mr" '{
        status: (.head_pipeline.status | normalise_status),
        sha: .head_pipeline.sha,
        url: .head_pipeline.web_url,
        jobs: [$jobs[] | {
            stage, name,
            status: (.status | normalise_status),
            allow_failure,
            url: .web_url,
            started_at, finished_at
        }]
    }' --argjson jobs "$gl_jobs"
}

# A retried job keeps its name; the last one is the attempt that counts.
gitlab_check_job() {
    gitlab_head_pipeline "$1" || return $?
    [ -n "$gl_pipeline" ] || forge_not_found "request !$1 has no pipeline"
    gl_jobs=$(forge_capture gitlab_api_all "$FORGE_API/pipelines/$gl_pipeline/jobs?per_page=100") || return $?
    gl_job=$(printf '%s\n' "$gl_jobs" |
        _jq -r --arg name "$2" '[.[] | select(.name == $name)] | sort_by(.id) | last | .id // empty')
    [ -n "$gl_job" ] || forge_not_found "pipeline $gl_pipeline has no job named '$2'"
}

gitlab_request_checks_log() {
    gitlab_check_job "$1" "$2" || return $?
    forge_capture gitlab_api "$FORGE_API/jobs/$gl_job/trace"
}

gitlab_request_checks_artifacts() {
    gitlab_check_job "$1" "$2" || return $?
    gl_archive="$3/$2.zip"
    if ! gitlab_api "$FORGE_API/jobs/$gl_job/artifacts" >"$gl_archive" 2>/dev/null; then
        rm -f "$gl_archive"
        forge_not_found "job '$2' of pipeline $gl_pipeline published no artifacts"
    fi
}

# --- comments ----------------------------------------------------------------------------

gitlab_request_comment_list() {
    gl_notes=$(forge_capture gitlab_api_all "$FORGE_API/merge_requests/$1/notes?sort=asc&per_page=100") ||
        return $?
    printf '%s\n' "$gl_notes" | _jq --arg url "$(gitlab_request_url_of "$1")" \
        "$GL_REQUEST_DEF [.[] | select((.system | not) and .type == null) | gl_note(\$url)]"
}

gitlab_request_comment_add() {
    gl_note=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1/notes" -X POST -f "body=$FORGE_BODY") ||
        return $?
    printf '%s\n' "$gl_note" | _jq --arg url "$(gitlab_request_url_of "$1")" "$GL_REQUEST_DEF gl_note(\$url)"
}

gitlab_request_comment_edit() {
    gl_note=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1/notes/$2" -X PUT -f "body=$FORGE_BODY") ||
        return $?
    printf '%s\n' "$gl_note" | _jq --arg url "$(gitlab_request_url_of "$1")" "$GL_REQUEST_DEF gl_note(\$url)"
}

# -f cannot express the nested position object (GitLab then silently creates an unanchored note),
# so the body goes as JSON through --input, and the answer is checked.
gitlab_request_comment_inline() {
    gl_mr=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1") || return $?
    gl_payload=$(printf '%s\n' "$gl_mr" | _jq --arg body "$FORGE_BODY" --arg path "$2" --argjson line "$3" '{
        body: $body,
        position: {
            position_type: "text",
            base_sha: .diff_refs.base_sha,
            head_sha: .diff_refs.head_sha,
            start_sha: .diff_refs.start_sha,
            new_path: $path,
            new_line: $line
        }
    }')
    gl_discussion=$(printf '%s\n' "$gl_payload" | forge_capture gitlab_api "$FORGE_API/merge_requests/$1/discussions" \
        -X POST --input - -H "Content-Type: application/json") || return $?
    gl_inline_path=$(printf '%s\n' "$gl_discussion" | _jq -r '.notes[0].position.new_path // empty')
    [ "$gl_inline_path" = "$2" ] || forge_die "the comment was created but not anchored to $2:$3"
    printf '%s\n' "$gl_discussion" | _jq --arg url "$(gitlab_request_url_of "$1")" '{
        thread_id: .id,
        comment_id: .notes[0].id,
        path: .notes[0].position.new_path,
        line: .notes[0].position.new_line,
        url: ($url + "#note_" + (.notes[0].id | tostring))
    }'
}

gitlab_request_thread_list() {
    gl_discussions=$(forge_capture gitlab_api_all "$FORGE_API/merge_requests/$1/discussions?per_page=100") ||
        return $?
    printf '%s\n' "$gl_discussions" | _jq '[.[] | select((.notes[0].system | not) and .notes[0].resolvable) | {
        thread_id: .id,
        resolved: (.notes[0].resolved // false),
        path: (.notes[0].position.new_path // null),
        line: (.notes[0].position.new_line // null),
        author: .notes[0].author.username,
        body: .notes[0].body,
        last_author: .notes[-1].author.username,
        last_body: .notes[-1].body
    }]'
}

gitlab_request_thread_reply() {
    gl_note=$(forge_capture gitlab_api "$FORGE_API/merge_requests/$1/discussions/$2/notes" -X POST \
        -f "body=$FORGE_BODY") || return $?
    printf '%s\n' "$gl_note" | _jq --arg t "$2" '{id, thread_id: $t, author: .author.username, body}'
}

gitlab_request_thread_set() {
    forge_capture gitlab_api "$FORGE_API/merge_requests/$1/discussions/$2" -X PUT -f "resolved=$3" >/dev/null
}

# --- labels ------------------------------------------------------------------------------

gitlab_request_label_add() {
    forge_capture glab mr update "$1" -R "$FORGE_R" --yes --label "$(forge_list_csv "$2")" >/dev/null
}

gitlab_request_label_remove() {
    forge_capture glab mr update "$1" -R "$FORGE_R" --yes --unlabel "$(forge_list_csv "$2")" >/dev/null
}
