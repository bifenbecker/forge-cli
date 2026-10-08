# shellcheck shell=sh

FORGE_EXIT_ERROR=1
FORGE_EXIT_USAGE=2
FORGE_EXIT_UNSUPPORTED=3
FORGE_EXIT_NOT_FOUND=4

forge_warn() {
    printf 'forge: %s\n' "$*" >&2
}

forge_die() {
    forge_warn "$@"
    exit "$FORGE_EXIT_ERROR"
}

forge_usage_die() {
    forge_warn "$@"
    if [ -n "${FORGE_PATH:-}" ]; then
        printf "Run 'forge %s --help' for usage.\n" "$FORGE_PATH" >&2
    else
        printf "Run 'forge --help' for usage.\n" >&2
    fi
    exit "$FORGE_EXIT_USAGE"
}

forge_unsupported() {
    forge_warn "${1:-forge ${FORGE_PATH:-}} is not supported on ${FORGE_PLATFORM:-this platform}"
    exit "$FORGE_EXIT_UNSUPPORTED"
}

forge_not_found() {
    forge_warn "$@"
    exit "$FORGE_EXIT_NOT_FOUND"
}

forge_require() {
    command -v "$1" >/dev/null 2>&1 || forge_die "$1 is required${2:+ ($2)}; install it and retry"
}

# Windows builds of jq write CRLF; -b exists only there and keeps output LF.
forge_jq_probe() {
    FORGE_JQ_BINARY=
    if command -v jq >/dev/null 2>&1 && command jq -b -n null >/dev/null 2>&1; then
        FORGE_JQ_BINARY=1
    fi
}

_jq() {
    if [ -n "${FORGE_JQ_BINARY:-}" ]; then
        command jq -b "$@"
    else
        command jq "$@"
    fi
}

forge_is_true() {
    case ${1:-} in
        '' | 0 | false | no) return 1 ;;
        *) return 0 ;;
    esac
}

forge_tmp() {
    mktemp 2>/dev/null || forge_die "cannot create a temporary file"
}

# Runs a command, passes its stdout through, and maps its failure to a forge exit code:
# 4 when the host said "not found", 1 otherwise. Stderr is replayed as is.
forge_capture() {
    forge_capture_err=$(forge_tmp)
    "$@" 2>"$forge_capture_err" && {
        rm -f "$forge_capture_err"
        return 0
    }
    forge_capture_status=$?
    cat "$forge_capture_err" >&2
    # GitHub answers 404 to a token without the needed scope: a failure, not "not found".
    if grep -qi 'needs the .* scope' "$forge_capture_err"; then
        rm -f "$forge_capture_err"
        return "$FORGE_EXIT_ERROR"
    fi
    if grep -qiE 'not found|404|could not resolve to|no .* found|does not exist' "$forge_capture_err"; then
        rm -f "$forge_capture_err"
        return "$FORGE_EXIT_NOT_FOUND"
    fi
    rm -f "$forge_capture_err"
    return "$forge_capture_status"
}

forge_urlencode() {
    printf '%s' "$1" | _jq -sRr '@uri'
}

# Newline-separated list helpers: arrays do not exist in POSIX sh.
forge_list_add() {
    if [ -n "$1" ]; then
        printf '%s\n%s' "$1" "$2"
    else
        printf '%s' "$2"
    fi
}

forge_list_csv() {
    printf '%s\n' "$1" | sed '/^$/d' | paste -sd ',' -
}

forge_list_json() {
    printf '%s\n' "$1" | sed '/^$/d' | _jq -R . | _jq -sc .
}

forge_current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || true
}
