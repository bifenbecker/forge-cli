# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/tag.sh

TAG_JSON_SHAPE='{name, sha, message, url}
  sha is the commit the tag points to, also for annotated tags. message is the annotation
  of an annotated tag, or null for a lightweight one.'

help_tag() {
    cat <<'EOF'
forge tag - tags on the remote

These commands act on the host through its API, not on local tags: no fetch or push needed.

COMMANDS
  list     List tags, newest commit first
  view     Show one tag
  create   Create a tag on the remote
  delete   Delete a tag on the remote

Run 'forge tag <command> --help' for details.
EOF
}

tag_require_name() {
    [ -n "$1" ] || forge_usage_die "<name> is required"
}

# After a change: the URL in text mode, the full tag in JSON mode.
tag_report() {
    if forge_json_mode; then
        forge_call tag_view "$1"
    else
        (FORGE_JSON=1 FORGE_JQ=.url && forge_call tag_view "$1")
    fi
}

help_tag_list() {
    cat <<EOF
NAME
  forge tag list - list tags on the remote

USAGE
  forge tag list [--limit <n>]

DESCRIPTION
  Lists the tags of the remote repository, newest first.

FLAGS
  -L, --limit <n>   At most this many tags (default 30)

OUTPUT
  Text: one tag name per line.
  JSON: array of $TAG_JSON_SHAPE

PLATFORM NOTES
  GitHub: ordered by the date of the tagged commit.
  GitLab: ordered by the last update of the tag.

EXAMPLES
  forge tag list
  forge tag list --limit 5 --json
  forge tag list --jq '.[] | select(.message != null) | .name'
EOF
}

cmd_tag_list() {
    opt_limit=30
    while [ $# -gt 0 ]; do
        case $1 in
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_int --limit "$opt_limit"
    forge_call tag_list
}

help_tag_view() {
    cat <<EOF
NAME
  forge tag view - show one tag on the remote

USAGE
  forge tag view <name>

DESCRIPTION
  Shows the commit and annotation of a tag. Exits 4 when the remote has no such tag.

ARGUMENTS
  <name>   Tag name, e.g. v1.2.0

OUTPUT
  Text: name, sha, message and url as "key: value" lines; the message may span lines.
  JSON: $TAG_JSON_SHAPE

EXAMPLES
  forge tag view v1.2.0
  forge tag view v1.2.0 --jq .sha
EOF
}

cmd_tag_view() {
    arg_name=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    tag_require_name "$arg_name"
    if forge_json_mode; then
        forge_call tag_view "$arg_name"
        return
    fi
    tag_view_doc=$(FORGE_JSON=1 FORGE_JQ='' forge_call tag_view "$arg_name") || exit $?
    printf '%s\n' "$tag_view_doc" |
        _jq -r '"name: \(.name)", "sha: \(.sha)", "message: \(.message // "")", "url: \(.url)"'
}

help_tag_create() {
    cat <<'EOF'
NAME
  forge tag create - create a tag on the remote

USAGE
  forge tag create <name> [--ref <sha|branch|tag>] [--message <text>]

DESCRIPTION
  Creates the tag directly on the host. Without --message the tag is lightweight; with it,
  annotated. Fails when the tag exists. Fetch afterwards to see it locally.

ARGUMENTS
  <name>                 Tag name, e.g. v1.2.0

FLAGS
  --ref <ref>            Commit SHA, branch or tag to tag; default: the default branch
  -m, --message <text>   Annotation; makes an annotated tag

OUTPUT
  Text: the URL of the tag.
  JSON: the new tag, as forge tag view --json.

PLATFORM NOTES
  GitHub: the annotation's tagger is the authenticated user.

EXAMPLES
  forge tag create v1.2.0 --ref 3f2a9c1 --message "Release 1.2.0"
  forge tag create nightly --ref develop --json
EOF
}

cmd_tag_create() {
    arg_name='' opt_ref='' opt_message=''
    while [ $# -gt 0 ]; do
        case $1 in
            -r | --ref | --target) forge_arg "$@"; opt_ref=$2; shift 2 ;;
            -m | --message) forge_arg "$@"; opt_message=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    tag_require_name "$arg_name"
    forge_call tag_create "$arg_name"
    tag_report "$arg_name"
}

help_tag_delete() {
    cat <<'EOF'
NAME
  forge tag delete - delete a tag on the remote

USAGE
  forge tag delete <name>

DESCRIPTION
  Deletes the tag on the host without asking. A release of the tag is not deleted (use
  'forge release delete <tag> --cleanup-tag' for both). Local tags are untouched.
  Exits 4 when the remote has no such tag.

ARGUMENTS
  <name>   Tag name

OUTPUT
  Text: nothing.
  JSON: {"name": "v1.2.0", "deleted": true}

EXAMPLES
  forge tag delete v1.2.0-rc.1
EOF
}

cmd_tag_delete() {
    arg_name=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    tag_require_name "$arg_name"
    forge_call tag_delete "$arg_name"
    if forge_json_mode; then
        _jq -n --arg name "$arg_name" '{name: $name, deleted: true}' | forge_emit '.'
    fi
}
