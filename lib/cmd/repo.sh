# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/repo.sh

REPO_JSON_SHAPE='{path, name, description, url, ssh_url, http_url, default_branch,
         visibility, archived}
  path is OWNER/REPO (GROUP/SUBGROUP/REPO on GitLab); name is its last segment.
  visibility is public, private or internal. description and default_branch may be null.'

help_repo() {
    cat <<'EOF'
forge repo - repositories (GitHub) and projects (GitLab)

<repo> is OWNER/REPO (GROUP/SUBGROUP/REPO on GitLab), HOST/OWNER/REPO, or a URL. A bare
OWNER/REPO lives on the host of --repo, else on the host of the current checkout.

COMMANDS
  view       Show the repository
  list       List repositories of a user, organization or group
  clone      Clone a repository
  fork       Fork a repository, optionally cloning the fork
  create     Create a repository
  delete     Delete a repository
  archive    Archive a repository (read-only)
  path       OWNER/REPO of the current repository, without asking the host
  url        Web address of the current repository, without asking the host
  blob-url   Permanent link to a file, or to lines of it, at a commit

Run 'forge repo <command> --help' for details.
EOF
}

# A positional <repo> names the repository to act on. Its host is its own when it carries one,
# else the host of --repo, else the host of the current checkout.
repo_target() {
    forge_parse_repo_flag "$1"
    if [ -n "$FORGE_HOST" ]; then
        FORGE_REPO_FLAG=$1
    elif [ -n "$FORGE_REPO_FLAG" ]; then
        forge_resolve_repo
        FORGE_REPO_PATH=$1
    else
        FORGE_REPO_FLAG=$1
    fi
}

# Destructive commands take only a full path: GitLab reads a bare number as a project id, and a
# bare name would be completed with whatever owner the CLI guesses.
repo_require_full() {
    case $1 in
        */*) ;;
        *) forge_usage_die "<repo> must be OWNER/REPO, HOST/OWNER/REPO or a URL, got '$1'" ;;
    esac
}

# list and create need only a host. Outside a checkout detection would stop at the missing
# remote, so a placeholder path lets it fall back to the default host.
repo_require_name() {
    case $2 in
        '' | */ | /* | *//*) forge_usage_die "$1 must be [OWNER/]NAME, got '$2'" ;;
    esac
}

# --- view --------------------------------------------------------------------------------

help_repo_view() {
    cat <<EOF
NAME
  forge repo view - show the repository

USAGE
  forge repo view [<repo>] [--web]

DESCRIPTION
  Shows the repository: description, visibility, default branch and clone URLs.

ARGUMENTS
  <repo>   Repository to show; default: the current one (or --repo)

FLAGS
  -w, --web  Open the repository in the browser instead

OUTPUT
  Text: the platform CLI's view (description and README).
  JSON: $REPO_JSON_SHAPE

EXAMPLES
  forge repo view
  forge repo view --jq .default_branch
  forge repo view octo-org/tools --json
  forge repo view --web
EOF
}

cmd_repo_view() {
    arg_repo='' opt_web=''
    while [ $# -gt 0 ]; do
        case $1 in
            -w | --web) opt_web=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_repo" ] || forge_unexpected "$1"; arg_repo=$1; shift ;;
        esac
    done
    [ -z "$opt_web" ] || ! forge_json_mode || forge_usage_die "--web and --json cannot be combined"
    [ -z "$arg_repo" ] || repo_target "$arg_repo"
    forge_call repo_view
}

# --- list --------------------------------------------------------------------------------

help_repo_list() {
    cat <<EOF
NAME
  forge repo list - list repositories of a user, organization or group

USAGE
  forge repo list [<owner>] [--limit <n>] [--visibility <visibility>]

DESCRIPTION
  Lists repositories owned by <owner>. Archived repositories are included. The host is the
  one of --repo or of the current checkout; outside a checkout, github.com (or GH_HOST) by
  default, or gitlab.com (or GITLAB_HOST) with FORGE_PLATFORM=gitlab.

ARGUMENTS
  <owner>                    User, organization or group; default: the authenticated user

FLAGS
  -L, --limit <n>            At most this many repositories (default 30)
  --visibility <visibility>  Only public, private or internal ones

OUTPUT
  Text: GitHub: gh's table. GitLab: one line per project: path, visibility, description,
        separated by tabs.
  JSON: array of $REPO_JSON_SHAPE

PLATFORM NOTES
  GitHub: the order is gh's (most recently pushed first).
  GitLab: <owner> is looked up as a group first (without subgroups), then as a user.
          Without <owner>, the projects you own. Newest first.

EXAMPLES
  forge repo list
  forge repo list octo-org --limit 100 --jq '.[].path'
  forge repo list --visibility private --json
EOF
}

cmd_repo_list() {
    arg_owner='' opt_limit=30 opt_visibility=''
    while [ $# -gt 0 ]; do
        case $1 in
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            --visibility) forge_arg "$@"; opt_visibility=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_owner" ] || forge_unexpected "$1"; arg_owner=$1; shift ;;
        esac
    done
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    [ -z "$opt_visibility" ] || forge_require_one_of --visibility "$opt_visibility" public private internal
    forge_host_only
    forge_call repo_list
}

# --- clone -------------------------------------------------------------------------------

help_repo_clone() {
    cat <<'EOF'
NAME
  forge repo clone - clone a repository

USAGE
  forge repo clone <repo> [<dir>]

DESCRIPTION
  Clones the repository with the protocol the platform CLI is configured for (ssh or https).
  When the repository is a fork, the platform CLI may also add an "upstream" remote.
  Works outside a checkout: a bare OWNER/REPO then goes to github.com (or GH_HOST), or to
  gitlab.com (or GITLAB_HOST) with FORGE_PLATFORM=gitlab.

ARGUMENTS
  <repo>   Repository to clone: OWNER/REPO, HOST/OWNER/REPO or a URL
  <dir>    Directory to clone into; default: the last segment of <repo>

OUTPUT
  Text: the directory cloned into. git's progress goes to stderr.
  JSON: {"dir": "...", "path": "OWNER/REPO"}

EXAMPLES
  forge repo clone octo-org/tools
  forge repo clone github.com/octo-org/tools .tmp/tools
  forge repo clone https://gitlab.example.com/group/sub/app
EOF
}

cmd_repo_clone() {
    arg_repo='' arg_dir=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                if [ -z "$arg_repo" ]; then
                    arg_repo=$1
                elif [ -z "$arg_dir" ]; then
                    arg_dir=$1
                else
                    forge_unexpected "$1"
                fi
                shift
                ;;
        esac
    done
    [ -n "$arg_repo" ] || forge_usage_die "<repo> is required"
    repo_target "$arg_repo"
    forge_resolve_repo
    [ -n "$arg_dir" ] || arg_dir=${FORGE_REPO_PATH##*/}
    [ ! -e "$arg_dir" ] || [ -z "$(ls -A -- "$arg_dir" 2>/dev/null)" ] ||
        forge_die "'$arg_dir' already exists and is not empty"
    forge_call repo_clone "$arg_dir"
    if forge_json_mode; then
        _jq -n --arg dir "$arg_dir" --arg path "$FORGE_REPO_PATH" '{dir: $dir, path: $path}' | forge_emit '.'
    else
        printf '%s\n' "$arg_dir"
    fi
}

# --- fork --------------------------------------------------------------------------------

help_repo_fork() {
    cat <<EOF
NAME
  forge repo fork - fork a repository

USAGE
  forge repo fork [<repo>] [--clone [--dir <path>]]

DESCRIPTION
  Creates a fork of the repository in your own namespace. The local checkout is not changed:
  no remote is added. With --clone, the fork is cloned into a new directory.

ARGUMENTS
  <repo>          Repository to fork; default: the current one (or --repo)

FLAGS
  --clone         Clone the fork after creating it
  --dir <path>    Directory for --clone; default: the fork's name. It must not exist or be
                  empty; this is checked before the fork is created (exit 1).

OUTPUT
  Text: the web URL of the fork; with --clone, then the directory on a second line.
  JSON: the fork, $REPO_JSON_SHAPE

PLATFORM NOTES
  GitHub: forking an already forked repository returns the existing fork.
  GitLab: forking a project you already forked fails (exit 1).
  Both: forks are created asynchronously; --clone retries for up to ~30 s while the fork's
        content is being copied.

EXAMPLES
  forge repo fork
  forge repo fork octo-org/tools --clone --dir .tmp/tools
  forge repo fork --jq .ssh_url
EOF
}

cmd_repo_fork() {
    arg_repo='' opt_clone='' opt_dir=''
    while [ $# -gt 0 ]; do
        case $1 in
            --clone) opt_clone=1; shift ;;
            --dir) forge_arg "$@"; opt_dir=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_repo" ] || forge_unexpected "$1"; arg_repo=$1; shift ;;
        esac
    done
    [ -z "$opt_dir" ] || [ -n "$opt_clone" ] || forge_usage_die "--dir needs --clone"
    [ -z "$arg_repo" ] || repo_target "$arg_repo"
    if [ -n "$opt_clone" ]; then
        # Checked before the fork exists: the default is the source's name, which the fork takes.
        forge_resolve_repo
        repo_fork_dir=${opt_dir:-${FORGE_REPO_PATH##*/}}
        [ ! -e "$repo_fork_dir" ] || [ -z "$(ls -A -- "$repo_fork_dir" 2>/dev/null)" ] ||
            forge_die "'$repo_fork_dir' already exists and is not empty"
    fi
    forge_call repo_fork
}

# --- create ------------------------------------------------------------------------------

help_repo_create() {
    cat <<'EOF'
NAME
  forge repo create - create a repository

USAGE
  forge repo create <name> (--public | --private | --internal) [--description <text>]

DESCRIPTION
  Creates an empty repository on the host. Nothing local is created or changed: no git init,
  no clone, no remote. Visibility has no default and must be given.

ARGUMENTS
  <name>                 NAME for your own namespace, or OWNER/NAME (organization or group;
                         GROUP/SUBGROUP/NAME on GitLab)

FLAGS
  --public                  Visible to everyone
  --private                 Visible only to members
  --internal                Visible to every signed-in user of the instance or enterprise
  -d, --description <text>  Description

OUTPUT
  Text: the web URL of the new repository.
  JSON: the new repository, {path, name, description, url, ssh_url, http_url, default_branch,
        visibility, archived}

PLATFORM NOTES
  GitHub: --internal works only for organizations of an enterprise account.
  The host is the one of --repo or of the current checkout; outside a checkout, github.com
  (or GH_HOST), or gitlab.com (or GITLAB_HOST) with FORGE_PLATFORM=gitlab.

EXAMPLES
  forge repo create tools --private
  forge repo create octo-org/tools --public --description "Shared tooling" --json
EOF
}

cmd_repo_create() {
    arg_name='' opt_visibility='' opt_description=''
    while [ $# -gt 0 ]; do
        case $1 in
            --public | --private | --internal)
                [ -z "$opt_visibility" ] || [ "$opt_visibility" = "${1#--}" ] ||
                    forge_usage_die "pick one visibility: --$opt_visibility and $1 were both given"
                opt_visibility=${1#--}
                shift
                ;;
            -d | --description) forge_arg "$@"; opt_description=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    [ -n "$arg_name" ] || forge_usage_die "<name> is required"
    repo_require_name "<name>" "$arg_name"
    [ -n "$opt_visibility" ] || forge_usage_die "a visibility is required: --public, --private or --internal"
    forge_host_only
    forge_call repo_create
}

# --- delete / archive --------------------------------------------------------------------

help_repo_delete() {
    cat <<'EOF'
NAME
  forge repo delete - delete a repository

USAGE
  forge repo delete <repo> --yes

DESCRIPTION
  Deletes the repository on the host, with its issues, requests and wiki. This cannot be
  undone. <repo> is required, even inside a checkout, and so is --yes.

ARGUMENTS
  <repo>   Repository to delete: OWNER/REPO, HOST/OWNER/REPO or a URL

FLAGS
  -y, --yes  Confirm the deletion; without it the command exits 2 and deletes nothing

OUTPUT
  Text: nothing.
  JSON: {"path": "OWNER/REPO", "deleted": true}

PLATFORM NOTES
  GitHub: needs the delete_repo token scope: gh auth refresh -s delete_repo
  GitLab: on instances with delayed deletion the project is only marked for deletion.

EXAMPLES
  forge repo delete me/scratch --yes
EOF
}

cmd_repo_delete() {
    arg_repo='' opt_yes=''
    while [ $# -gt 0 ]; do
        case $1 in
            -y | --yes) opt_yes=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_repo" ] || forge_unexpected "$1"; arg_repo=$1; shift ;;
        esac
    done
    [ -n "$arg_repo" ] || forge_usage_die "<repo> is required"
    repo_require_full "$arg_repo"
    [ -n "$opt_yes" ] || forge_usage_die "deleting $arg_repo cannot be undone: pass --yes to confirm"
    repo_target "$arg_repo"
    forge_call repo_delete
    if forge_json_mode; then
        _jq -n --arg path "$FORGE_REPO_PATH" '{path: $path, deleted: true}' | forge_emit '.'
    fi
}

help_repo_archive() {
    cat <<EOF
NAME
  forge repo archive - archive a repository

USAGE
  forge repo archive <repo> --yes

DESCRIPTION
  Archives the repository: it becomes read-only (no pushes, issues or requests) but stays
  visible. Undo it in the host's web settings. <repo> is required, and so is --yes.

ARGUMENTS
  <repo>   Repository to archive: OWNER/REPO, HOST/OWNER/REPO or a URL

FLAGS
  -y, --yes  Confirm; without it the command exits 2 and changes nothing

OUTPUT
  Text: the web URL of the repository.
  JSON: the repository after the change, $REPO_JSON_SHAPE

PLATFORM NOTES
  GitHub: archiving an archived repository is a no-op.
  GitLab: this is the project archive API, not 'glab repo archive' (which downloads a
          tarball of the code).

EXAMPLES
  forge repo archive octo-org/old-tools --yes
EOF
}

cmd_repo_archive() {
    arg_repo='' opt_yes=''
    while [ $# -gt 0 ]; do
        case $1 in
            -y | --yes) opt_yes=1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_repo" ] || forge_unexpected "$1"; arg_repo=$1; shift ;;
        esac
    done
    [ -n "$arg_repo" ] || forge_usage_die "<repo> is required"
    repo_require_full "$arg_repo"
    [ -n "$opt_yes" ] || forge_usage_die "archiving $arg_repo makes it read-only: pass --yes to confirm"
    repo_target "$arg_repo"
    forge_call repo_archive
}

# --- path / url / blob-url: no host call ---------------------------------------------------

help_repo_path() {
    cat <<'EOF'
NAME
  forge repo path - path of the current repository

USAGE
  forge repo path

DESCRIPTION
  Prints the repository path read from the git remote (or --repo), without asking the host
  and without needing gh or glab. A remote with an ssh alias host is resolved as by every
  other command (git config forge.host).

OUTPUT
  Text: OWNER/REPO, or GROUP/SUBGROUP/REPO on GitLab.
  JSON: {"path": "OWNER/REPO", "host": "github.com", "platform": "github"}

EXAMPLES
  forge repo path
  forge repo path --jq .host
EOF
}

cmd_repo_path() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_resolve_repo
    if forge_json_mode; then
        _jq -n --arg path "$FORGE_REPO_PATH" --arg host "$FORGE_HOST" --arg platform "$FORGE_PLATFORM" \
            '{path: $path, host: $host, platform: $platform}' | forge_emit '.'
    else
        printf '%s\n' "$FORGE_REPO_PATH"
    fi
}

help_repo_url() {
    cat <<'EOF'
NAME
  forge repo url - web address of the current repository

USAGE
  forge repo url

DESCRIPTION
  Prints https://HOST/PATH of the repository from the git remote (or --repo), without asking
  the host. The host keeps a port when the remote had one on http(s).

OUTPUT
  Text: the URL.
  JSON: {"url": "https://github.com/OWNER/REPO"}

EXAMPLES
  forge repo url
  forge repo url --repo octo-org/tools
EOF
}

cmd_repo_url() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_resolve_repo
    repo_url_value="https://$FORGE_HOST/$FORGE_REPO_PATH"
    if forge_json_mode; then
        _jq -n --arg url "$repo_url_value" '{url: $url}' | forge_emit '.'
    else
        printf '%s\n' "$repo_url_value"
    fi
}

help_repo_blob_url() {
    cat <<'EOF'
NAME
  forge repo blob-url - permanent link to a file or lines at a commit

USAGE
  forge repo blob-url <sha> <path> [<from> [<to>]]

DESCRIPTION
  Builds the web link to <path> as of <sha>, optionally to one line or a range of lines.
  No host call: neither the commit nor the file is checked to exist. Pass a full commit SHA
  for a link that never changes; a branch name gives a link that moves with the branch.

ARGUMENTS
  <sha>    Commit SHA (or any ref)
  <path>   File path from the repository root, e.g. src/main.c; a leading ./ or / is dropped
  <from>   First line to highlight
  <to>     Last line to highlight; must not be before <from>

OUTPUT
  Text: the URL.
  JSON: {"url": "..."}

PLATFORM NOTES
  GitHub: https://HOST/OWNER/REPO/blob/<sha>/<path>#L10-L15
  GitLab: https://HOST/GROUP/REPO/-/blob/<sha>/<path>#L10-15

EXAMPLES
  forge repo blob-url "$(git rev-parse HEAD)" lib/core/util.sh
  forge repo blob-url "$(git rev-parse HEAD)" lib/core/util.sh 10 15
EOF
}

cmd_repo_blob_url() {
    arg_sha='' arg_path='' arg_from='' arg_to='' repo_blob_n=0
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *)
                repo_blob_n=$((repo_blob_n + 1))
                case $repo_blob_n in
                    1) arg_sha=$1 ;;
                    2) arg_path=$1 ;;
                    3) arg_from=$1 ;;
                    4) arg_to=$1 ;;
                    *) forge_unexpected "$1" ;;
                esac
                shift
                ;;
        esac
    done
    [ -n "$arg_sha" ] || forge_usage_die "<sha> is required"
    [ -n "$arg_path" ] || forge_usage_die "<path> is required"
    arg_path=${arg_path#./}
    arg_path=${arg_path#/}
    [ -z "$arg_from" ] || forge_require_int "<from>" "$arg_from"
    if [ -n "$arg_to" ]; then
        forge_require_int "<to>" "$arg_to"
        [ "$arg_to" -ge "$arg_from" ] || forge_usage_die "<to> ($arg_to) is before <from> ($arg_from)"
    fi
    forge_resolve_repo
    repo_blob_base="https://$FORGE_HOST/$FORGE_REPO_PATH"
    repo_blob_anchor=''
    case $FORGE_PLATFORM in
        github)
            [ -z "$arg_from" ] || repo_blob_anchor="#L$arg_from${arg_to:+-L$arg_to}"
            repo_blob_url="$repo_blob_base/blob/$arg_sha/$arg_path$repo_blob_anchor"
            ;;
        gitlab)
            [ -z "$arg_from" ] || repo_blob_anchor="#L$arg_from${arg_to:+-$arg_to}"
            repo_blob_url="$repo_blob_base/-/blob/$arg_sha/$arg_path$repo_blob_anchor"
            ;;
    esac
    if forge_json_mode; then
        _jq -n --arg url "$repo_blob_url" '{url: $url}' | forge_emit '.'
    else
        printf '%s\n' "$repo_blob_url"
    fi
}
