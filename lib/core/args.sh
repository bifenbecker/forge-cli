# shellcheck shell=sh

# Helpers for command parsers. Global flags are stripped earlier, in forge_main.

forge_arg() {
    [ $# -ge 2 ] || forge_usage_die "$1 needs a value"
}

forge_unknown_flag() {
    forge_usage_die "unknown flag '$1'"
}

forge_unexpected() {
    forge_usage_die "unexpected argument '$1'"
}

# Usage: forge_read_body_file <path|->  — sets FORGE_BODY.
forge_read_body_file() {
    if [ "$1" = - ]; then
        FORGE_BODY=$(cat)
    else
        [ -f "$1" ] || forge_die "file not found: $1"
        FORGE_BODY=$(cat -- "$1")
    fi
    FORGE_BODY_SET=1
}

forge_require_body() {
    [ -n "${FORGE_BODY_SET:-}" ] || forge_usage_die "${1:-text} is required: pass --body <text> or --body-file <path|->"
    [ -n "$FORGE_BODY" ] || forge_usage_die "${1:-text} is empty"
}

forge_require_int() {
    case $2 in
        '' | *[!0-9]*) forge_usage_die "$1 must be a number, got '$2'" ;;
    esac
}

forge_require_one_of() {
    forge_roo_name=$1
    forge_roo_value=$2
    shift 2
    for forge_roo_allowed in "$@"; do
        [ "$forge_roo_value" = "$forge_roo_allowed" ] && return 0
    done
    forge_usage_die "$forge_roo_name must be one of: $*"
}
