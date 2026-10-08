# shellcheck shell=sh

# Prepended to every filter. Unknown statuses pass through unchanged so a new one shows as itself.
FORGE_JQ_DEFS='
def normalise_status:
    if . == null then null
    else ascii_downcase | {
        "created": "pending", "waiting_for_resource": "pending", "preparing": "pending",
        "pending": "pending", "scheduled": "pending", "queued": "pending", "requested": "pending",
        "waiting": "pending", "expected": "pending",
        "running": "running", "in_progress": "running",
        "success": "success", "pass": "success", "neutral": "success",
        "failed": "failed", "fail": "failed", "failure": "failed", "timed_out": "failed",
        "startup_failure": "failed", "action_required": "failed", "error": "failed",
        "canceled": "canceled", "cancelled": "canceled", "canceling": "canceled", "cancel": "canceled",
        "skipped": "skipped", "skipping": "skipped", "stale": "skipped",
        "manual": "manual"
    }[.] // .
    end;
def gh_run_status:
    if .status == "completed" then (.conclusion | normalise_status) else (.status | normalise_status) end;
def lower_or_null: if . == null or . == "" then null else ascii_downcase end;
'

# Usage: <json on stdin> | forge_emit <filter> [jq options...]
# Applies the shape filter, then the user's --jq expression if one was given.
forge_emit() {
    forge_emit_filter=$1
    shift
    if [ -n "${FORGE_JQ:-}" ]; then
        _jq -r "$FORGE_JQ_DEFS ($forge_emit_filter) | ($FORGE_JQ)" "$@"
    else
        _jq "$FORGE_JQ_DEFS $forge_emit_filter" "$@"
    fi
}

# Same as forge_emit, for a document already held in a variable.
forge_emit_doc() {
    forge_emit_doc_json=$1
    shift
    printf '%s\n' "$forge_emit_doc_json" | forge_emit "$@"
}

forge_json_mode() {
    [ -n "${FORGE_JSON:-}" ]
}
