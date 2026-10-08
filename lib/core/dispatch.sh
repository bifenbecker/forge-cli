# shellcheck shell=sh

forge_main() {
    FORGE_JSON=
    FORGE_JQ=
    FORGE_HELP=
    FORGE_PATH=
    FORGE_GROUP=
    FORGE_BODY=
    FORGE_BODY_SET=
    FORGE_SHOW_VERSION=
    forge_jq_probe

    # Pull global flags out of the argument list, wherever they are. The list is rotated:
    # each argument is shifted off the front and, unless it is global, appended to the back.
    forge_n=$#
    while [ "$forge_n" -gt 0 ]; do
        forge_a=$1
        shift
        forge_n=$((forge_n - 1))
        case $forge_a in
            --)
                set -- "$@" --
                while [ "$forge_n" -gt 0 ]; do
                    set -- "$@" "$1"
                    shift
                    forge_n=$((forge_n - 1))
                done
                ;;
            --json) FORGE_JSON=1 ;;
            --jq | -R | --repo)
                [ "$forge_n" -gt 0 ] || forge_usage_die "$forge_a needs a value"
                case $forge_a in
                    --jq) FORGE_JQ=$1 FORGE_JSON=1 ;;
                    *) FORGE_REPO=$1 ;;
                esac
                shift
                forge_n=$((forge_n - 1))
                ;;
            --jq=*) FORGE_JQ=${forge_a#--jq=} FORGE_JSON=1 ;;
            --repo=*) FORGE_REPO=${forge_a#--repo=} ;;
            -h | --help) FORGE_HELP=1 ;;
            --version | -V) FORGE_SHOW_VERSION=1 ;;
            --*=*) set -- "$@" "${forge_a%%=*}" "${forge_a#*=}" ;;
            *) set -- "$@" "$forge_a" ;;
        esac
    done

    forge_dispatch "$@"
}

forge_token_ok() {
    case $1 in
        '' | *[!a-z0-9-]* | -*) return 1 ;;
    esac
    return 0
}

forge_fn_exists() {
    command -v "$1" >/dev/null 2>&1
}

forge_dispatch() {
    if [ -n "$FORGE_SHOW_VERSION" ]; then
        cmd_version
        return 0
    fi
    if [ $# -eq 0 ]; then
        help_root
        return 0
    fi

    forge_group=$1
    case $forge_group in
        pr | mr) forge_group=request ;;
    esac
    forge_token_ok "$forge_group" || forge_usage_die "unknown command '$1'"
    if [ -f "$FORGE_HOME/lib/cmd/$forge_group.sh" ]; then
        . "$FORGE_HOME/lib/cmd/$forge_group.sh"
    fi
    forge_node=$(printf '%s' "$forge_group" | tr '-' '_')
    forge_fn_exists "help_$forge_node" || forge_usage_die "unknown command '$1'"
    FORGE_GROUP=$forge_group
    FORGE_PATH=$forge_group
    shift

    while [ $# -gt 0 ] && forge_token_ok "$1"; do
        forge_next="${forge_node}_$(printf '%s' "$1" | tr '-' '_')"
        forge_fn_exists "help_$forge_next" || break
        forge_node=$forge_next
        FORGE_PATH="$FORGE_PATH $1"
        shift
    done

    if [ -n "$FORGE_HELP" ]; then
        forge_show_help "$forge_node"
        return 0
    fi
    if forge_fn_exists "cmd_$forge_node"; then
        "cmd_$forge_node" "$@"
        return
    fi
    if [ $# -gt 0 ]; then
        forge_usage_die "unknown command 'forge $FORGE_PATH $1'"
    fi
    forge_show_help "$forge_node"
}
