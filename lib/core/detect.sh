# shellcheck shell=sh

forge_remote_name() {
    if [ -n "${FORGE_REMOTE:-}" ]; then
        printf '%s' "$FORGE_REMOTE"
    else
        git config --get forge.remote 2>/dev/null || printf 'origin'
    fi
}

# Host and path of a git URL: git@host:a/b.git, ssh://git@host:22/a/b.git, https://host:8443/a/b
# The port is kept for http(s), where it addresses the API too, and dropped for ssh.
forge_url_host() {
    case $1 in
        http://* | https://*) forge_uh=$(printf '%s\n' "$1" | sed 's#^[a-zA-Z]*://##; s#^[^@/]*@##; s#/.*$##') ;;
        *://*) forge_uh=$(printf '%s\n' "$1" | sed 's#^[a-zA-Z0-9+.-]*://##; s#^[^@/]*@##; s#[:/].*$##') ;;
        *) forge_uh=$(printf '%s\n' "$1" | sed 's#^[^@]*@##; s#:.*$##') ;;
    esac
    # SSH-over-443 endpoints serve the same hosts.
    case $forge_uh in
        ssh.github.com) forge_uh=github.com ;;
        altssh.gitlab.com) forge_uh=gitlab.com ;;
    esac
    printf '%s\n' "$forge_uh"
}

forge_url_path() {
    case $1 in
        *://*) printf '%s\n' "$1" | sed 's#^[a-zA-Z0-9+.-]*://##; s#^[^/]*/##; s#\.git$##; s#/$##' ;;
        *) printf '%s\n' "$1" | sed 's#^[^:]*:##; s#\.git$##; s#/$##' ;;
    esac
}

forge_platform_of_host() {
    case ${1%%:*} in
        github.com | *.github.com | *.ghe.com) printf 'github' ;;
        gitlab.com | gitlab.* | *.gitlab.com) printf 'gitlab' ;;
        *)
            if command -v glab >/dev/null 2>&1 && glab auth status 2>&1 | grep -qF "$1"; then
                printf 'gitlab'
            elif command -v gh >/dev/null 2>&1 && gh auth status 2>&1 | grep -qF "$1"; then
                printf 'github'
            fi
            ;;
    esac
}

forge_default_host() {
    case $1 in
        github) printf '%s' "${GH_HOST:-github.com}" ;;
        gitlab) forge_url_host "${GITLAB_HOST:-gitlab.com}" | sed 's#/.*##' ;;
    esac
}

# Splits --repo into host and path. A first segment with a dot is a host when a path follows it.
forge_parse_repo_flag() {
    case $1 in
        *://*)
            FORGE_HOST=$(forge_url_host "$1")
            FORGE_REPO_PATH=$(forge_url_path "$1")
            return
            ;;
    esac
    forge_prf_first=${1%%/*}
    forge_prf_rest=${1#*/}
    case $forge_prf_first in
        *.*)
            case $forge_prf_rest in
                */*)
                    FORGE_HOST=$forge_prf_first
                    FORGE_REPO_PATH=$forge_prf_rest
                    return
                    ;;
            esac
            ;;
    esac
    FORGE_HOST=
    FORGE_REPO_PATH=$1
}

forge_validate_platform() {
    case $1 in
        github | gitlab) ;;
        *) forge_die "unknown platform '$1': use github or gitlab" ;;
    esac
}

# Sets FORGE_PLATFORM, FORGE_HOST, FORGE_REPO_PATH. Idempotent.
forge_resolve_repo() {
    [ -n "${FORGE_RESOLVED:-}" ] && return 0
    FORGE_HOST=
    FORGE_REPO_PATH=
    forge_rr_url=''
    if [ -n "${FORGE_REPO_FLAG:-}" ]; then
        forge_parse_repo_flag "$FORGE_REPO_FLAG"
        # A bare OWNER/REPO lives on the same host as the current checkout, when there is one.
        if [ -z "$FORGE_HOST" ]; then
            forge_rr_url=$(git remote get-url "$(forge_remote_name)" 2>/dev/null || true)
            [ -z "$forge_rr_url" ] || FORGE_HOST=$(forge_url_host "$forge_rr_url")
        fi
    else
        forge_rr_remote=$(forge_remote_name)
        forge_rr_url=$(git remote get-url "$forge_rr_remote" 2>/dev/null) ||
            forge_die "no git remote '$forge_rr_remote' here; run inside a repository or pass --repo [HOST/]OWNER/REPO"
        case $forge_rr_url in
            file://* | /* | ./* | ../* | [A-Za-z]:/* | [A-Za-z]:\\*)
                forge_die "remote '$forge_rr_remote' is a local path ($forge_rr_url); pass --repo HOST/OWNER/REPO" ;;
        esac
        FORGE_HOST=$(forge_url_host "$forge_rr_url")
        FORGE_REPO_PATH=$(forge_url_path "$forge_rr_url")
    fi

    # An ssh alias such as git@github-work:o/r names no real host; this says which one it is.
    # It applies to hosts read from the remote, not to one given in --repo.
    if [ -n "$forge_rr_url" ]; then
        forge_rr_override=${FORGE_HOSTNAME:-$(git config --get forge.host 2>/dev/null || true)}
        [ -z "$forge_rr_override" ] || FORGE_HOST=$forge_rr_override
    fi

    if [ -z "${FORGE_PLATFORM:-}" ]; then
        FORGE_PLATFORM=$(git config --get forge.platform 2>/dev/null || true)
    fi
    if [ -z "$FORGE_PLATFORM" ] && [ -n "$FORGE_HOST" ]; then
        FORGE_PLATFORM=$(forge_platform_of_host "$FORGE_HOST")
    fi
    if [ -z "$FORGE_PLATFORM" ] && [ -z "$FORGE_HOST" ]; then
        FORGE_PLATFORM=github
    fi
    [ -n "$FORGE_PLATFORM" ] ||
        forge_die "cannot tell whether $FORGE_HOST is GitHub or GitLab; set FORGE_PLATFORM=github|gitlab or 'git config forge.platform gitlab'"
    forge_validate_platform "$FORGE_PLATFORM"
    [ -n "$FORGE_HOST" ] || FORGE_HOST=$(forge_default_host "$FORGE_PLATFORM")
    [ -n "$FORGE_REPO_PATH" ] || forge_die "cannot work out the repository path"
    FORGE_RESOLVED=1
}

# Loads the platform layer and checks its tools. Called by every command that talks to the host.
forge_init() {
    [ -n "${FORGE_INITIALISED:-}" ] && return 0
    forge_resolve_repo
    forge_require jq "forge shapes every answer with it"
    . "$FORGE_HOME/lib/$FORGE_PLATFORM/core.sh"
    "${FORGE_PLATFORM}_init"
    FORGE_INITIALISED=1
}

# Calls <platform>_<name>, loading lib/<platform>/<group>.sh first. Exit 3 when it does not exist.
forge_call() {
    forge_call_name=$1
    shift
    forge_init
    forge_call_file="$FORGE_HOME/lib/$FORGE_PLATFORM/$FORGE_GROUP.sh"
    if [ -f "$forge_call_file" ] && [ "${FORGE_LOADED_GROUP:-}" != "$FORGE_PLATFORM/$FORGE_GROUP" ]; then
        . "$forge_call_file"
        FORGE_LOADED_GROUP="$FORGE_PLATFORM/$FORGE_GROUP"
    fi
    command -v "${FORGE_PLATFORM}_$forge_call_name" >/dev/null 2>&1 || forge_unsupported
    "${FORGE_PLATFORM}_$forge_call_name" "$@"
}
