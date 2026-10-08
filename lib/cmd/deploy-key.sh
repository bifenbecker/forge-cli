# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/deploy-key.sh

DEPLOY_KEY_JSON_SHAPE='{id, title, key, read_only, created_at}
  key is the public key text; read_only is false for a key that may push.'

help_deploy_key() {
    cat <<'EOF'
forge deploy-key - SSH deploy keys of the repository

A deploy key gives one machine SSH access to this repository only, without a user account.
<id> is the numeric key id shown by 'forge deploy-key list'.

COMMANDS
  list      List deploy keys
  add       Add a public key as a deploy key
  delete    Remove a deploy key

Run 'forge deploy-key <command> --help' for details.
EOF
}

# Reads a public key file (or - for stdin) into deploy_key_text; refuses private keys.
deploy_key_read() {
    if [ "$1" = - ]; then
        deploy_key_text=$(cat)
    else
        [ -f "$1" ] || forge_usage_die "key file not found: $1"
        deploy_key_text=$(cat -- "$1")
    fi
    case $deploy_key_text in
        '') forge_usage_die "key file is empty: $1" ;;
        *PRIVATE\ KEY*) forge_usage_die "$1 is a private key; pass the public key (.pub)" ;;
    esac
}

# --- list --------------------------------------------------------------------------------

help_deploy_key_list() {
    cat <<EOF
NAME
  forge deploy-key list - list the repository's deploy keys

USAGE
  forge deploy-key list

DESCRIPTION
  Lists every deploy key of the repository.

OUTPUT
  Text: the platform CLI's table on GitHub; on GitLab one key per line, tab-separated:
        id, title, read-only or read-write, created_at.
  JSON: array of $DEPLOY_KEY_JSON_SHAPE

PLATFORM NOTES
  GitLab: lists the keys enabled for the project; read_only is the inverse of can_push.

EXAMPLES
  forge deploy-key list
  forge deploy-key list --jq '.[] | select(.read_only == false) | .title'
EOF
}

cmd_deploy_key_list() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_call deploy_key_list
}

# --- add ---------------------------------------------------------------------------------

help_deploy_key_add() {
    cat <<EOF
NAME
  forge deploy-key add - add a public key as a deploy key

USAGE
  forge deploy-key add <keyfile> --title <text> [--write]

DESCRIPTION
  Adds the public key in <keyfile> as a deploy key. The key is read-only unless --write is
  given. A private key file is refused (exit 2).

ARGUMENTS
  <keyfile>          Public key file, e.g. ~/.ssh/deploy.pub, or - for standard input

FLAGS
  -t, --title <text>  Name of the key; required
  -w, --write         Allow the key to push (aliases: --allow-write, --can-push)

OUTPUT
  Text: the id of the new key.
  JSON: $DEPLOY_KEY_JSON_SHAPE

EXAMPLES
  forge deploy-key add ci_deploy.pub --title "CI runner"
  forge deploy-key add ci_deploy.pub --title "release bot" --write --json
EOF
}

cmd_deploy_key_add() {
    arg_keyfile='' opt_title='' opt_write=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -w | --write | --allow-write | --can-push) opt_write=1; shift ;;
            -) [ -z "$arg_keyfile" ] || forge_unexpected "$1"; arg_keyfile=$1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_keyfile" ] || forge_unexpected "$1"; arg_keyfile=$1; shift ;;
        esac
    done
    [ -n "$arg_keyfile" ] || forge_usage_die "<keyfile> is required"
    [ -n "$opt_title" ] || forge_usage_die "--title is required"
    deploy_key_read "$arg_keyfile"
    forge_call deploy_key_add
}

# --- delete ------------------------------------------------------------------------------

help_deploy_key_delete() {
    cat <<'EOF'
NAME
  forge deploy-key delete - remove a deploy key

USAGE
  forge deploy-key delete <id>

DESCRIPTION
  Removes the deploy key from the repository. Exits 4 when there is no key with that id.

ARGUMENTS
  <id>   Key id, from 'forge deploy-key list'

OUTPUT
  Text and JSON: nothing; the exit code tells the result.

PLATFORM NOTES
  GitLab: a key shared with other projects is only disabled for this one.

EXAMPLES
  forge deploy-key delete 123456
EOF
}

cmd_deploy_key_delete() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$arg_id" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$arg_id"
    forge_call deploy_key_delete "$arg_id"
}
