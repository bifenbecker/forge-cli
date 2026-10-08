# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/release.sh

RELEASE_JSON_SHAPE='{tag, name, notes, url, author, draft, prerelease, created_at, published_at,
         assets: [{name, url}]}
  notes is null when empty. url is the release page; assets[].url downloads the file. GitLab
  has no drafts or pre-releases: draft is always false and prerelease always null there.'

help_release() {
    cat <<'EOF'
forge release - releases and their assets

A release is identified by its git tag (<tag>), e.g. v1.2.0.

COMMANDS
  list       List releases
  view       Show one release; exits 4 when it does not exist
  latest     The latest published release
  create     Create a release, and its tag when the tag does not exist yet
  edit       Change the title, notes or state of a release
  publish    Create the release of an existing tag, or replace the notes of the one there is
  delete     Delete a release, optionally with its tag
  upload     Attach files to a release
  download   Download the files of a release

Run 'forge release <command> --help' for details.
EOF
}

# After a change: the URL in text mode, the full release in JSON mode.
release_report() {
    if forge_json_mode; then
        forge_call release_view "$1"
    else
        forge_call release_url "$1"
    fi
}

# Shared by create, edit and publish: --body is the forge name, --notes the gh/glab one.
release_parse_body() {
    case $1 in
        -b | --body | -n | --notes) FORGE_BODY=$2; FORGE_BODY_SET=1 ;;
        -F | --body-file | --notes-file) forge_read_body_file "$2" ;;
    esac
}

release_require_tag() {
    [ -n "$1" ] || forge_usage_die "<tag> is required"
}

release_require_files() {
    while IFS= read -r release_file; do
        [ -z "$release_file" ] || [ -f "$release_file" ] || forge_die "file not found: $release_file"
    done <<EOF
$1
EOF
}

# --- list --------------------------------------------------------------------------------

help_release_list() {
    cat <<EOF
NAME
  forge release list - list releases

USAGE
  forge release list [--limit <n>]

DESCRIPTION
  Lists releases of the repository, newest first.

FLAGS
  -L, --limit <n>   At most this many releases (default 30)

OUTPUT
  Text: the platform CLI's table. On GitLab with --limit above 100 (one glab page), forge's
        own: one release per line, tab-separated: tag, name, released_at.
  JSON: array of $RELEASE_JSON_SHAPE

PLATFORM NOTES
  GitHub: drafts are listed too (to users who can see them); newest by creation date.
  GitLab: newest by release date.

EXAMPLES
  forge release list
  forge release list --limit 5 --json
  forge release list --jq '.[0].tag'
EOF
}

cmd_release_list() {
    opt_limit=30
    while [ $# -gt 0 ]; do
        case $1 in
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    forge_call release_list
}

# --- view / latest -----------------------------------------------------------------------

help_release_view() {
    cat <<EOF
NAME
  forge release view - show one release

USAGE
  forge release view <tag>

DESCRIPTION
  Shows the title, notes, author, dates and assets of the release of <tag>.
  The exit code answers "does this release exist": 0 yes, 4 no, 1 the host could not be
  asked (authentication, network). A tag without a release is "no".

ARGUMENTS
  <tag>   Tag of the release, e.g. v1.2.0

OUTPUT
  Text: the platform CLI's view.
  JSON: $RELEASE_JSON_SHAPE

EXAMPLES
  forge release view v1.2.0
  forge release view v1.2.0 --jq '.notes'
  forge release view v1.2.0 >/dev/null 2>&1; echo \$?   # 0 exists, 4 missing, 1 cannot tell
EOF
}

cmd_release_view() {
    arg_tag=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_tag" ] || forge_unexpected "$1"; arg_tag=$1; shift ;;
        esac
    done
    release_require_tag "$arg_tag"
    forge_call release_view "$arg_tag"
}

help_release_latest() {
    cat <<EOF
NAME
  forge release latest - the latest published release

USAGE
  forge release latest

DESCRIPTION
  Finds the release the host marks as latest. Exits 4 when the repository has no release.

OUTPUT
  Text: its tag, e.g. v1.2.0
  JSON: $RELEASE_JSON_SHAPE

PLATFORM NOTES
  GitHub: the release marked "Latest"; drafts and pre-releases never are.
  GitLab: the release with the newest release date.

EXAMPLES
  forge release latest
  forge release latest --jq '.assets[].url'
EOF
}

cmd_release_latest() {
    case ${1-} in
        '') ;;
        -*) forge_unknown_flag "$1" ;;
        *) forge_unexpected "$1" ;;
    esac
    forge_call release_latest
}

# --- create / edit / publish -------------------------------------------------------------

help_release_create() {
    cat <<'EOF'
NAME
  forge release create - create a release

USAGE
  forge release create <tag> [<file>...] [--title <text>] [--body <text> | --body-file <path|->]
                       [--target <ref>] [--draft] [--prerelease]

DESCRIPTION
  Creates the release of <tag> and attaches the given files. When <tag> does not exist on
  the remote yet, it is created on --target. Fails when the release already exists; use
  'forge release publish' to create-or-update.

ARGUMENTS
  <tag>                  Tag of the release
  <file>                 Files to attach as assets

FLAGS
  -t, --title <text>     Title; default: the tag
  -b, --body <text>      Release notes (alias: -n, --notes); default: empty
  -F, --body-file <path|->
                         Release notes from a file, or - for stdin (alias: --notes-file)
  --target <ref>         Branch or commit SHA to tag when <tag> does not exist;
                         default: the default branch. Ignored when the tag exists.
  -d, --draft            Save as an unpublished draft (GitHub only)
  -p, --prerelease       Mark as a pre-release (GitHub only)

OUTPUT
  Text: the URL of the release.
  JSON: the new release, as forge release view --json.

PLATFORM NOTES
  GitLab: has no drafts or pre-releases; --draft and --prerelease exit 3.
  GitLab: files are uploaded to the project and linked to the release.

EXAMPLES
  forge release create v1.2.0 --title "v1.2.0" --body-file notes.md
  forge release create v1.3.0-rc.1 --target develop --prerelease
  forge release create v1.2.0 dist/forge.tar.gz dist/forge.zip --json
EOF
}

cmd_release_create() {
    arg_tag='' opt_files='' opt_title='' opt_target='' opt_draft='' opt_prerelease=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body | -n | --notes | -F | --body-file | --notes-file)
                forge_arg "$@"; release_parse_body "$1" "$2"; shift 2 ;;
            --target) forge_arg "$@"; opt_target=$2; shift 2 ;;
            -d | --draft) opt_draft=1; shift ;;
            -p | --prerelease) opt_prerelease=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_tag" ]; then
                    arg_tag=$1
                else
                    opt_files=$(forge_list_add "$opt_files" "$1")
                fi
                shift
                ;;
        esac
    done
    release_require_tag "$arg_tag"
    release_require_files "$opt_files"
    forge_call release_create "$arg_tag"
    release_report "$arg_tag"
}

help_release_edit() {
    cat <<'EOF'
NAME
  forge release edit - change a release

USAGE
  forge release edit <tag> [--title <text>] [--body <text> | --body-file <path|->]
                     [--draft | --no-draft] [--prerelease | --no-prerelease]

DESCRIPTION
  Changes only what is given; everything else stays. At least one flag is required.

ARGUMENTS
  <tag>                  Tag of the release

FLAGS
  -t, --title <text>     New title
  -b, --body <text>      New release notes, replacing the old (alias: -n, --notes)
  -F, --body-file <path|->
                         New release notes from a file, or - for stdin (alias: --notes-file)
  --draft                Turn back into a draft (GitHub only)
  --no-draft             Publish a draft (GitHub only)
  --prerelease           Mark as a pre-release (GitHub only)
  --no-prerelease        Mark as a full release (GitHub only)

OUTPUT
  Text: the URL of the release.
  JSON: the release after the change, as forge release view --json.

PLATFORM NOTES
  GitLab: the draft and pre-release flags exit 3; title and notes work.

EXAMPLES
  forge release edit v1.2.0 --title "v1.2.0 (LTS)"
  forge release edit v1.2.0 --body-file - < notes.md
  forge release edit v1.3.0 --no-draft
EOF
}

cmd_release_edit() {
    arg_tag='' opt_title='' opt_draft='' opt_prerelease=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body | -n | --notes | -F | --body-file | --notes-file)
                forge_arg "$@"; release_parse_body "$1" "$2"; shift 2 ;;
            --draft) opt_draft=true; shift ;;
            --no-draft) opt_draft=false; shift ;;
            --prerelease) opt_prerelease=true; shift ;;
            --no-prerelease) opt_prerelease=false; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_tag" ] || forge_unexpected "$1"; arg_tag=$1; shift ;;
        esac
    done
    release_require_tag "$arg_tag"
    [ -n "$opt_title$opt_draft$opt_prerelease${FORGE_BODY_SET:-}" ] ||
        forge_usage_die "nothing to change: pass --title, --body, --draft or --prerelease"
    forge_call release_edit "$arg_tag"
    release_report "$arg_tag"
}

help_release_publish() {
    cat <<'EOF'
NAME
  forge release publish - create or update the release of an existing tag

USAGE
  forge release publish <tag> [--title <text>] [--body <text> | --body-file <path|->]

DESCRIPTION
  Makes sure <tag> has a published release with these notes, whether or not one exists:
  creates it when missing, otherwise replaces its notes (and title, when given) and, on
  GitHub, publishes it if it is a draft. Safe to run again. <tag> must already exist on the
  remote; push it first. Exits 4 when it does not.

ARGUMENTS
  <tag>                  An existing tag on the remote

FLAGS
  -t, --title <text>     Title; default on creation: the tag; on update: unchanged
  -b, --body <text>      Release notes (alias: -n, --notes); on update, unchanged when omitted
  -F, --body-file <path|->
                         Release notes from a file, or - for stdin (alias: --notes-file)

OUTPUT
  Text: the URL of the release.
  JSON: the release, as forge release view --json.

EXAMPLES
  forge release publish v1.2.0 --title v1.2.0 --body-file .tmp/notes.md
  forge release publish v1.2.0 --body "Fixes the installer" --json
EOF
}

cmd_release_publish() {
    arg_tag='' opt_title=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -b | --body | -n | --notes | -F | --body-file | --notes-file)
                forge_arg "$@"; release_parse_body "$1" "$2"; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_tag" ] || forge_unexpected "$1"; arg_tag=$1; shift ;;
        esac
    done
    release_require_tag "$arg_tag"
    forge_call release_publish "$arg_tag"
    release_report "$arg_tag"
}

# --- delete ------------------------------------------------------------------------------

help_release_delete() {
    cat <<'EOF'
NAME
  forge release delete - delete a release

USAGE
  forge release delete <tag> [--cleanup-tag]

DESCRIPTION
  Deletes the release of <tag> without asking. The git tag stays unless --cleanup-tag is
  given. Exits 4 when there is no such release.

ARGUMENTS
  <tag>           Tag of the release

FLAGS
  --cleanup-tag   Also delete the tag on the remote (alias: --with-tag)

OUTPUT
  Text: nothing.
  JSON: {"tag": "v1.2.0", "deleted": true, "tag_deleted": false}

EXAMPLES
  forge release delete v1.2.0-rc.1
  forge release delete v1.2.0-rc.1 --cleanup-tag
EOF
}

cmd_release_delete() {
    arg_tag='' opt_cleanup_tag=''
    while [ $# -gt 0 ]; do
        case $1 in
            --cleanup-tag | --with-tag) opt_cleanup_tag=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_tag" ] || forge_unexpected "$1"; arg_tag=$1; shift ;;
        esac
    done
    release_require_tag "$arg_tag"
    forge_call release_delete "$arg_tag"
    if forge_json_mode; then
        _jq -n --arg tag "$arg_tag" --arg cleanup "$opt_cleanup_tag" \
            '{tag: $tag, deleted: true, tag_deleted: ($cleanup != "")}' | forge_emit '.'
    fi
}

# --- assets ------------------------------------------------------------------------------

help_release_upload() {
    cat <<'EOF'
NAME
  forge release upload - attach files to a release

USAGE
  forge release upload <tag> <file>... [--clobber]

DESCRIPTION
  Uploads each file as an asset of the existing release of <tag>. The asset is named after
  the file. Exits 4 when there is no such release.

ARGUMENTS
  <tag>       Tag of the release
  <file>      One or more files

FLAGS
  --clobber   Replace assets of the same name instead of failing (GitHub only)

OUTPUT
  Text: the URL of the release.
  JSON: the release with its assets, as forge release view --json.

PLATFORM NOTES
  GitLab: files are uploaded to the project and linked to the release; --clobber exits 3.

EXAMPLES
  forge release upload v1.2.0 dist/forge.tar.gz
  forge release upload v1.2.0 dist/*.zip --clobber --jq '.assets[].name'
EOF
}

cmd_release_upload() {
    arg_tag='' opt_files='' opt_clobber=''
    while [ $# -gt 0 ]; do
        case $1 in
            --clobber) opt_clobber=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_tag" ]; then
                    arg_tag=$1
                else
                    opt_files=$(forge_list_add "$opt_files" "$1")
                fi
                shift
                ;;
        esac
    done
    release_require_tag "$arg_tag"
    [ -n "$opt_files" ] || forge_usage_die "at least one <file> is required"
    release_require_files "$opt_files"
    forge_call release_upload "$arg_tag"
    release_report "$arg_tag"
}

help_release_download() {
    cat <<'EOF'
NAME
  forge release download - download the files of a release

USAGE
  forge release download [<tag>] [--pattern <glob>] [--dir <path>]

DESCRIPTION
  Downloads the assets of a release into a directory, which is created when missing.
  Existing files of the same name make it fail.

ARGUMENTS
  <tag>              Tag of the release; default: the latest release (as forge release latest)

FLAGS
  -p, --pattern <glob>   Only assets whose name matches, e.g. '*.tar.gz'; default: all
  -D, --dir <path>       Where the files go (default: the current directory)

OUTPUT
  Text: the directory.
  JSON: {"tag": "v1.2.0", "dir": "dist"}

PLATFORM NOTES
  GitLab: only asset links are downloaded, not the generated source archives.

EXAMPLES
  forge release download v1.2.0 --dir .tmp/v1.2.0
  forge release download --pattern '*.tar.gz'
EOF
}

cmd_release_download() {
    arg_tag='' opt_pattern='' opt_dir=.
    while [ $# -gt 0 ]; do
        case $1 in
            -p | --pattern) forge_arg "$@"; opt_pattern=$2; shift 2 ;;
            -D | --dir) forge_arg "$@"; opt_dir=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_tag" ] || forge_unexpected "$1"; arg_tag=$1; shift ;;
        esac
    done
    [ -n "$opt_dir" ] || forge_usage_die "--dir is empty"
    if [ -z "$arg_tag" ]; then
        arg_tag=$(FORGE_JSON='' FORGE_JQ='' forge_call release_latest) || exit $?
    fi
    mkdir -p -- "$opt_dir"
    forge_call release_download "$arg_tag"
    if forge_json_mode; then
        _jq -n --arg tag "$arg_tag" --arg dir "$opt_dir" '{tag: $tag, dir: $dir}' | forge_emit '.'
    else
        printf '%s\n' "$opt_dir"
    fi
}
