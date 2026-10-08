# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/label.sh

LABEL_JSON_SHAPE='{name, color, description}
  color is 6 lowercase hex digits without "#" (d73a4a); description may be null.'

help_label() {
    cat <<'EOF'
forge label - labels of the repository

These are the repository's own labels. To put labels on a request, see 'forge request label'.

COMMANDS
  list     List labels
  create   Create a label
  edit     Rename a label or change its colour or description
  delete   Delete a label

Run 'forge label <command> --help' for details.
EOF
}

# Colour to 6 lowercase hex digits: accepts d73a4a, #D73A4A and the short form #fa0.
label_color() {
    label_color_hex=${1#\#}
    case $label_color_hex in
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
            label_color_hex=$(printf '%s\n' "$label_color_hex" | sed 's/\(.\)\(.\)\(.\)/\1\1\2\2\3\3/')
            ;;
        [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
        *) forge_usage_die "--color must be a hex colour such as d73a4a or #d73a4a, got '$1'" ;;
    esac
    printf '%s' "$label_color_hex" | tr 'A-F' 'a-f'
}

# Text mode prints the name of the label a command changed; JSON mode the label.
label_report() {
    if forge_json_mode; then
        forge_emit_doc "$1" '.'
    else
        printf '%s\n' "$1" | _jq -r '.name'
    fi
}

# --- list --------------------------------------------------------------------------------

help_label_list() {
    cat <<EOF
NAME
  forge label list - list labels of the repository

USAGE
  forge label list [--limit <n>] [--search <text>]

DESCRIPTION
  Lists the repository's labels.

FLAGS
  -L, --limit <n>        At most this many labels (default 30)
  -S, --search <text>    Only labels whose name or description contains this text

OUTPUT
  Text: GitHub: gh's table. GitLab: one line per label: name, color, description,
        separated by tabs.
  JSON: array of $LABEL_JSON_SHAPE

PLATFORM NOTES
  GitHub: in creation order. GitLab: by name; labels inherited from groups are included.

EXAMPLES
  forge label list
  forge label list --search bug --json
  forge label list --limit 200 --jq '.[].name'
EOF
}

cmd_label_list() {
    opt_limit=30 opt_search=''
    while [ $# -gt 0 ]; do
        case $1 in
            -L | --limit) forge_arg "$@"; opt_limit=$2; shift 2 ;;
            -S | --search) forge_arg "$@"; opt_search=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_require_int --limit "$opt_limit"
    [ "$opt_limit" -gt 0 ] || forge_usage_die "--limit must be at least 1"
    forge_call label_list
}

# --- create ------------------------------------------------------------------------------

help_label_create() {
    cat <<EOF
NAME
  forge label create - create a label

USAGE
  forge label create <name> [--color <hex>] [--description <text>]

DESCRIPTION
  Creates a label in the repository. Fails (exit 1) when a label with this name exists.

ARGUMENTS
  <name>                    Label name; may contain spaces and colons ("type: bug")

FLAGS
  -c, --color <hex>         Colour as hex: d73a4a, #d73a4a or #d4a; default: see PLATFORM NOTES
  -d, --description <text>  Description

OUTPUT
  Text: the label name.
  JSON: $LABEL_JSON_SHAPE

PLATFORM NOTES
  Without --color: GitHub uses ededed, GitLab 428bca.

EXAMPLES
  forge label create bug --color d73a4a --description "Something is broken"
  forge label create "priority: high" --color "#b60205" --json
EOF
}

cmd_label_create() {
    arg_name='' opt_color='' opt_description=''
    while [ $# -gt 0 ]; do
        case $1 in
            -c | --color) forge_arg "$@"; opt_color=$(label_color "$2") || exit $?; shift 2 ;;
            -d | --description) forge_arg "$@"; opt_description=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    [ -n "$arg_name" ] || forge_usage_die "<name> is required"
    label_doc=$(forge_call label_create) || exit $?
    label_report "$label_doc"
}

# --- edit --------------------------------------------------------------------------------

help_label_edit() {
    cat <<EOF
NAME
  forge label edit - change a label

USAGE
  forge label edit <name> [--name <new>] [--color <hex>] [--description <text>]

DESCRIPTION
  Renames a label or changes its colour or description. Only what is given changes; at
  least one flag is required. Requests and issues carrying the label keep it after a rename.

ARGUMENTS
  <name>                    Current label name

FLAGS
  -n, --name <new>          New name
  -c, --color <hex>         New colour as hex: d73a4a, #d73a4a or #d4a
  -d, --description <text>  New description; "" clears it

OUTPUT
  Text: the label name after the change.
  JSON: $LABEL_JSON_SHAPE

EXAMPLES
  forge label edit bug --color ee0701
  forge label edit wip --name "status: wip" --description ""
EOF
}

cmd_label_edit() {
    arg_name='' opt_name='' opt_color='' opt_description='' opt_description_set=''
    while [ $# -gt 0 ]; do
        case $1 in
            -n | --name) forge_arg "$@"; opt_name=$2; shift 2 ;;
            -c | --color) forge_arg "$@"; opt_color=$(label_color "$2") || exit $?; shift 2 ;;
            -d | --description) forge_arg "$@"; opt_description=$2; opt_description_set=1; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    [ -n "$arg_name" ] || forge_usage_die "<name> is required"
    [ -n "$opt_name$opt_color$opt_description_set" ] ||
        forge_usage_die "nothing to change: pass --name, --color or --description"
    label_doc=$(forge_call label_edit) || exit $?
    label_report "$label_doc"
}

# --- delete ------------------------------------------------------------------------------

help_label_delete() {
    cat <<'EOF'
NAME
  forge label delete - delete a label

USAGE
  forge label delete <name>

DESCRIPTION
  Deletes the label from the repository and so from every request and issue carrying it.
  Exits 4 when there is no such label.

ARGUMENTS
  <name>   Label name

OUTPUT
  Text: nothing.
  JSON: {"name": "...", "deleted": true}

PLATFORM NOTES
  GitLab: a label inherited from a group cannot be deleted here; delete it in the group.

EXAMPLES
  forge label delete wip
EOF
}

cmd_label_delete() {
    arg_name=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    [ -n "$arg_name" ] || forge_usage_die "<name> is required"
    forge_call label_delete
    if forge_json_mode; then
        _jq -n --arg name "$arg_name" '{name: $name, deleted: true}' | forge_emit '.'
    fi
}
