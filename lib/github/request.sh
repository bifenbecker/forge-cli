# shellcheck shell=sh

GH_REQUEST_FIELDS=number,title,state,isDraft,author,headRefName,baseRefName,url,body,labels,assignees,reviewRequests,headRefOid,createdAt,updatedAt,mergedAt,closedAt,mergeable,latestReviews

GH_REQUEST_DEF='
def gh_request: {
    id: .number,
    title,
    state: (.state | ascii_downcase),
    draft: .isDraft,
    author: .author.login,
    source_branch: .headRefName,
    target_branch: .baseRefName,
    url,
    description: .body,
    labels: [.labels[].name],
    assignees: [.assignees[].login],
    # Pending requests plus whoever already reviewed: GitLab keeps both in .reviewers.
    reviewers: ([.reviewRequests[] | .login // .slug // .name]
        + [.latestReviews[] | .author.login | select(. != null)] | unique),
    sha: .headRefOid,
    created_at: .createdAt,
    updated_at: .updatedAt,
    merged_at: .mergedAt,
    closed_at: .closedAt,
    mergeable: (if .mergeable == "MERGEABLE" then true elif .mergeable == "CONFLICTING" then false else null end)
};
def gh_comment: {id, author: .user.login, body, created_at, updated_at, url: .html_url};
'


github_request_list() {
    set -- pr list -R "$FORGE_R" --limit "$opt_limit"
    gh_request_search=$opt_search
    case $opt_state in
        closed)
            # gh counts merged requests as closed; GitLab does not.
            set -- "$@" --state closed
            gh_request_search="${gh_request_search:+$gh_request_search }is:unmerged"
            ;;
        *) set -- "$@" --state "$opt_state" ;;
    esac
    [ -z "$opt_author" ] || set -- "$@" --author "$opt_author"
    [ -z "$opt_assignee" ] || set -- "$@" --assignee "$opt_assignee"
    [ -z "$opt_source" ] || set -- "$@" --head "$opt_source"
    [ -z "$opt_target" ] || set -- "$@" --base "$opt_target"
    [ -z "$opt_draft" ] || set -- "$@" --draft
    [ -z "$gh_request_search" ] || set -- "$@" --search "$gh_request_search"
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || set -- "$@" --label "$gh_label"
    done <<EOF
$opt_labels
EOF
    if forge_json_mode; then
        gh_list_doc=$(forge_capture gh "$@" --json "$GH_REQUEST_FIELDS") || return $?
        forge_emit_doc "$gh_list_doc" "$GH_REQUEST_DEF [.[] | gh_request]"
    else
        gh "$@"
    fi
}

github_request_view() {
    if ! forge_json_mode; then
        set -- pr view "$1" -R "$FORGE_R"
        [ -z "${opt_comments:-}" ] || set -- "$@" --comments
        [ -z "${opt_web:-}" ] || set -- "$@" --web
        forge_capture gh "$@"
        return
    fi
    gh_view_doc=$(forge_capture gh pr view "$1" -R "$FORGE_R" \
        --json "$GH_REQUEST_FIELDS,reviewDecision") || return $?
    # reviewDecision is empty where no review is required; the reviews themselves still count.
    forge_emit_doc "$gh_view_doc" "$GH_REQUEST_DEF gh_request + {
        approved: (if (.reviewDecision // \"\") != \"\" then .reviewDecision == \"APPROVED\"
            else ([.latestReviews[].state] | any(. == \"APPROVED\") and all(. != \"CHANGES_REQUESTED\")) end),
        approved_by: [.latestReviews[] | select(.state == \"APPROVED\") | .author.login],
        decision: (.reviewDecision | lower_or_null)
    }"
}

github_request_find() {
    set -- pr list -R "$FORGE_R" --head "$1" --state "$2" --limit 1 --json number
    # gh counts merged requests as closed; GitLab does not.
    [ "$8" != closed ] || set -- "$@" --search is:unmerged
    gh_find_doc=$(forge_capture gh "$@") || return $?
    printf '%s\n' "$gh_find_doc" | _jq -r '.[0].number // empty'
}

github_request_url() {
    forge_capture gh pr view "$1" -R "$FORGE_R" --json url --jq .url
}

# GitHub does not create a missing label on the fly; GitLab does.
github_ensure_labels() {
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || gh label create "$gh_label" -R "$FORGE_R" >/dev/null 2>&1 || true
    done <<EOF
$1
EOF
}

github_request_create() {
    set -- pr create -R "$FORGE_R" --head "$opt_source"
    if [ -n "$opt_title" ]; then
        set -- "$@" --title "$opt_title" --body "${FORGE_BODY:-}"
    else
        set -- "$@" --fill
    fi
    [ -z "$opt_target" ] || set -- "$@" --base "$opt_target"
    [ -z "$opt_draft" ] || set -- "$@" --draft
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    github_ensure_labels "$opt_labels"
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --label "$gh_item"
    done <<EOF
$opt_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --assignee "$gh_item"
    done <<EOF
$opt_assignees
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --reviewer "$gh_item"
    done <<EOF
$opt_reviewers
EOF
    [ -z "$opt_delete_branch" ] ||
        forge_warn "GitHub has no per-request delete-branch; use 'forge request merge --delete-branch' or the repository setting"
    gh_create_out=$(forge_capture gh "$@") || return $?
    gh_create_url=$(printf '%s\n' "$gh_create_out" | grep -Eo 'https?://[^[:space:]]+/pull/[0-9]+' | tail -n 1)
    [ -n "$gh_create_url" ] || forge_die "gh did not report the new pull request: $gh_create_out"
    printf '%s' "${gh_create_url##*/}"
}

github_request_edit() {
    set -- pr edit "$1" -R "$FORGE_R"
    gh_edit_base=$#
    [ -z "$opt_title" ] || set -- "$@" --title "$opt_title"
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --body "$FORGE_BODY"
    [ -z "$opt_target" ] || set -- "$@" --base "$opt_target"
    [ -z "$opt_milestone" ] || set -- "$@" --milestone "$opt_milestone"
    github_ensure_labels "$opt_add_labels"
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --add-label "$gh_item"
    done <<EOF
$opt_add_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --remove-label "$gh_item"
    done <<EOF
$opt_remove_labels
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --add-assignee "$gh_item"
    done <<EOF
$opt_add_assignees
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --remove-assignee "$gh_item"
    done <<EOF
$opt_remove_assignees
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --add-reviewer "$gh_item"
    done <<EOF
$opt_add_reviewers
EOF
    while IFS= read -r gh_item; do
        [ -z "$gh_item" ] || set -- "$@" --remove-reviewer "$gh_item"
    done <<EOF
$opt_remove_reviewers
EOF
    [ "$#" -gt "$gh_edit_base" ] || return 0
    forge_capture gh "$@" >/dev/null
}

github_request_close() {
    set -- pr close "$1" -R "$FORGE_R"
    [ -z "$opt_comment" ] || set -- "$@" --comment "$opt_comment"
    [ -z "$opt_delete_branch" ] || set -- "$@" --delete-branch
    forge_capture gh "$@" >/dev/null
}

github_request_reopen() {
    forge_capture gh pr reopen "$1" -R "$FORGE_R" >/dev/null
}

github_request_merge() {
    gh_merge_id=$1
    set -- pr merge "$1" -R "$FORGE_R" "--$opt_strategy"
    [ -z "$opt_delete_branch" ] || set -- "$@" --delete-branch
    [ -z "$opt_sha" ] || set -- "$@" --match-head-commit "$opt_sha"
    [ -z "$opt_auto" ] || set -- "$@" --auto
    if [ -n "$opt_message" ]; then
        # gh takes subject and body separately: first line, then the rest after blank lines.
        gh_merge_subject=$(printf '%s\n' "$opt_message" | sed -n 1p)
        gh_merge_body=$(printf '%s\n' "$opt_message" | sed 1d | sed '/./,$!d')
        set -- "$@" --subject "$gh_merge_subject" --body "$gh_merge_body"
    fi
    forge_capture gh "$@" >&2 || return $?
    gh_merge_doc=$(forge_capture gh pr view "$gh_merge_id" -R "$FORGE_R" \
        --json state,mergeCommit,autoMergeRequest) || return $?
    forge_emit_doc "$gh_merge_doc" '{
        state: (.state | ascii_downcase),
        sha: (.mergeCommit.oid // null),
        auto_merge: (.autoMergeRequest != null)
    }'
}

github_request_ready() {
    set -- pr ready "$1" -R "$FORGE_R"
    [ -z "$opt_undo" ] || set -- "$@" --undo
    forge_capture gh "$@" >/dev/null
}

github_request_checkout() {
    set -- pr checkout "$1" -R "$FORGE_R"
    [ -z "$opt_branch" ] || set -- "$@" --branch "$opt_branch"
    forge_capture gh "$@"
}

github_request_diff() {
    if [ -z "$opt_name_only" ]; then
        forge_capture gh pr diff "$1" -R "$FORGE_R" --color never
        return
    fi
    gh_diff_names=$(forge_capture gh pr diff "$1" -R "$FORGE_R" --name-only) || return $?
    if forge_json_mode; then
        printf '%s\n' "$gh_diff_names" | sed '/^$/d' | _jq -R . | _jq -s . | forge_emit '.'
    else
        printf '%s\n' "$gh_diff_names"
    fi
}

github_request_approve() {
    set -- pr review "$1" -R "$FORGE_R" --approve
    [ -z "${FORGE_BODY_SET:-}" ] || set -- "$@" --body "$FORGE_BODY"
    forge_capture gh "$@" >/dev/null
}

# --- checks ------------------------------------------------------------------------------

# gh exits 1 on failed checks and 8 on pending ones; with a JSON answer both are answers, not
# errors. "No checks reported" is an empty answer. Anything else is a real failure.
github_checks_doc() {
    gh_cd_err=$(forge_tmp)
    gh_cd_status=0
    gh_cd_out=$(gh pr checks "$1" -R "$FORGE_R" --json name,state,bucket,link,startedAt,completedAt,workflow \
        2>"$gh_cd_err") || gh_cd_status=$?
    case $gh_cd_status in
        0 | 1 | 8)
            if printf '%s\n' "$gh_cd_out" | _jq -e 'type == "array"' >/dev/null 2>&1; then
                rm -f "$gh_cd_err"
                printf '%s\n' "$gh_cd_out"
                return 0
            fi
            ;;
    esac
    if grep -qi 'no checks reported' "$gh_cd_err"; then
        rm -f "$gh_cd_err"
        printf '[]\n'
        return 0
    fi
    cat "$gh_cd_err" >&2
    if grep -qiE 'not found|could not resolve to' "$gh_cd_err"; then
        rm -f "$gh_cd_err"
        return "$FORGE_EXIT_NOT_FOUND"
    fi
    rm -f "$gh_cd_err"
    [ "$gh_cd_status" -ne 0 ] || gh_cd_status=1
    return "$gh_cd_status"
}

github_request_checks() {
    gh_checks=$(github_checks_doc "$1") || return $?
    gh_checks_sha=$(forge_capture gh pr view "$1" -R "$FORGE_R" --json headRefOid --jq .headRefOid) ||
        return $?
    # No single run speaks for all checks on GitHub, so the overall status is aggregated.
    forge_emit_doc "$gh_checks" '{
        status: (
            if length == 0 then "none"
            elif any(.[]; .bucket == "fail") then "failed"
            elif any(.[]; .bucket == "pending") then "pending"
            elif any(.[]; .bucket == "cancel") then "canceled"
            elif any(.[]; .bucket == "pass") then "success"
            else (.[0].bucket | normalise_status)
            end
        ),
        sha: $sha,
        url: $url,
        jobs: [.[] | {
            stage: .workflow,
            name,
            status: (.bucket | normalise_status),
            allow_failure: null,
            url: .link,
            started_at: .startedAt,
            finished_at: .completedAt
        }]
    }' --arg sha "$gh_checks_sha" --arg url "$(github_web_url)/pull/$1/checks"
}

github_check_link() {
    gh_checks=$(github_checks_doc "$1") || exit $?
    gh_link=$(printf '%s\n' "$gh_checks" |
        _jq -r --arg name "$2" '[.[] | select(.name == $name)] | last | .link // empty')
    [ -n "$gh_link" ] || forge_not_found "request $1 has no check named '$2'"
    case $gh_link in
        */actions/runs/*) ;;
        *) forge_unsupported "logs and artifacts of a check not run by GitHub Actions ($gh_link)" ;;
    esac
}

github_request_checks_log() {
    github_check_link "$1" "$2"
    forge_capture gh run view -R "$FORGE_R" --job "${gh_link##*/job/}" --log
}

github_request_checks_artifacts() {
    github_check_link "$1" "$2"
    gh_run_id=${gh_link#*/actions/runs/}
    gh_run_id=${gh_run_id%%/*}
    forge_capture gh run download "$gh_run_id" -R "$FORGE_R" --dir "$3" >&2
}

# --- comments ----------------------------------------------------------------------------

github_request_comment_list() {
    gh_comments=$(forge_capture github_api "$FORGE_API/issues/$1/comments?per_page=100" --paginate) ||
        return $?
    printf '%s\n' "$gh_comments" | _jq -s "$GH_REQUEST_DEF [.[][] | gh_comment]"
}

github_request_comment_add() {
    gh_comment=$(forge_capture github_api "$FORGE_API/issues/$1/comments" -X POST -f "body=$FORGE_BODY") ||
        return $?
    printf '%s\n' "$gh_comment" | _jq "$GH_REQUEST_DEF gh_comment"
}

github_request_comment_edit() {
    # Conversation comments and review comments live under different endpoints.
    if gh_comment=$(github_api "$FORGE_API/issues/comments/$2" -X PATCH -f "body=$FORGE_BODY" 2>/dev/null); then
        :
    else
        gh_comment=$(forge_capture github_api "$FORGE_API/pulls/comments/$2" -X PATCH -f "body=$FORGE_BODY") ||
            return $?
    fi
    printf '%s\n' "$gh_comment" | _jq "$GH_REQUEST_DEF gh_comment"
}

GH_THREADS_QUERY='
query($owner: String!, $repo: String!, $num: Int!, $endCursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $num) {
      reviewThreads(first: 100, after: $endCursor) {
        nodes {
          id
          isResolved
          path
          line
          originalLine
          comments(first: 1) { nodes { databaseId body author { login } } }
          last: comments(last: 1) { nodes { body author { login } } }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}'

github_threads_raw() {
    forge_capture github_api graphql --paginate --slurp \
        -f owner="$(github_owner)" -f repo="$(github_name)" -F num="$1" -f query="$GH_THREADS_QUERY"
}

github_request_thread_list() {
    gh_threads=$(github_threads_raw "$1") || return $?
    printf '%s\n' "$gh_threads" | _jq '[.[] | .data.repository.pullRequest.reviewThreads.nodes[] | {
        thread_id: .id,
        resolved: .isResolved,
        path,
        line: (.line // .originalLine),
        author: .comments.nodes[0].author.login,
        body: .comments.nodes[0].body,
        last_author: .last.nodes[0].author.login,
        last_body: .last.nodes[0].body
    }]'
}

github_request_comment_inline() {
    gh_inline_sha=$(forge_capture gh pr view "$1" -R "$FORGE_R" --json headRefOid --jq .headRefOid) ||
        return $?
    gh_inline=$(forge_capture github_api "$FORGE_API/pulls/$1/comments" -X POST \
        -f "body=$FORGE_BODY" -f "commit_id=$gh_inline_sha" -f "path=$2" -f side=RIGHT -F "line=$3") ||
        return $?
    gh_inline_path=$(printf '%s\n' "$gh_inline" | _jq -r '.path // empty')
    [ "$gh_inline_path" = "$2" ] || forge_die "the comment was created but not anchored to $2:$3"
    gh_inline_id=$(printf '%s\n' "$gh_inline" | _jq -r '.id')
    # REST returns the comment; its thread id is only visible through GraphQL.
    gh_threads=$(github_threads_raw "$1") || return $?
    gh_thread_id=$(printf '%s\n' "$gh_threads" | _jq -r --argjson cid "$gh_inline_id" \
        '[.[] | .data.repository.pullRequest.reviewThreads.nodes[] |
          select(.comments.nodes[0].databaseId == $cid) | .id] | first // empty')
    printf '%s\n' "$gh_inline" | _jq --arg t "$gh_thread_id" \
        '{thread_id: (if $t == "" then null else $t end), comment_id: .id, path, line, url: .html_url}'
}

github_request_thread_reply() {
    gh_reply=$(forge_capture github_api graphql -f threadId="$2" -f body="$FORGE_BODY" -f query='
        mutation($threadId: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
            comment { databaseId body author { login } }
          }
        }') || return $?
    printf '%s\n' "$gh_reply" | _jq --arg t "$2" '.data.addPullRequestReviewThreadReply.comment |
        {id: .databaseId, thread_id: $t, author: .author.login, body}'
}

github_request_thread_set() {
    if [ "$3" = true ]; then
        gh_thread_mutation=resolveReviewThread
    else
        gh_thread_mutation=unresolveReviewThread
    fi
    forge_capture github_api graphql -f threadId="$2" -f query="
        mutation(\$threadId: ID!) {
          $gh_thread_mutation(input: {threadId: \$threadId}) { thread { isResolved } }
        }" >/dev/null
}

# --- labels ------------------------------------------------------------------------------

github_request_label_add() {
    github_ensure_labels "$2"
    set -- pr edit "$1" -R "$FORGE_R" --add-label "$(forge_list_csv "$2")"
    forge_capture gh "$@" >/dev/null
}

github_request_label_remove() {
    gh_label_id=$1
    while IFS= read -r gh_label; do
        [ -z "$gh_label" ] || gh pr edit "$gh_label_id" -R "$FORGE_R" --remove-label "$gh_label" >/dev/null 2>&1 || true
    done <<EOF
$2
EOF
}
