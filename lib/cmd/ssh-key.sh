# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/ssh-key.sh

SSH_KEY_JSON_SHAPE='{id, title, key, created_at}
  key is the public key text.'

help_ssh_key() {
    cat <<'EOF'
forge ssh-key - SSH keys of the authenticated user's account

These keys belong to the account gh or glab is logged in as, not to the repository; they
grant access to everything that account can reach. For one repository use 'forge deploy-key'.
The host is still taken from the repository (or --repo).

COMMANDS
  list      List the account's SSH keys
  add       Add a public key to the account
  delete    Remove a key from the account

Run 'forge ssh-key <command> --help' for details.
EOF
}

# Reads a public key file (or - for stdin) into ssh_key_text; refuses private keys.
ssh_key_read() {
    if [ "$1" = - ]; then
        ssh_key_text=$(cat)
    else
        [ -f "$1" ] || forge_usage_die "key file not found: $1"
        ssh_key_text=$(cat -- "$1")
    fi
    case $ssh_key_text in
        '') forge_usage_die "key file is empty: $1" ;;
        *PRIVATE\ KEY*) forge_usage_die "$1 is a private key; pass the public key (.pub)" ;;
    esac
}

# --- list --------------------------------------------------------------------------------

help_ssh_key_list() {
    cat <<EOF
NAME
  forge ssh-key list - list the authenticated user's SSH keys

USAGE
  forge ssh-key list

DESCRIPTION
  Lists the SSH keys of the account gh or glab is logged in as on the repository's host.

OUTPUT
  Text: the platform CLI's table on GitHub; on GitLab one key per line, tab-separated:
        id, title, created_at.
  JSON: array of $SSH_KEY_JSON_SHAPE

PLATFORM NOTES
  GitHub: the gh token needs the admin:public_key scope ('gh auth refresh -s admin:public_key');
          without it the command exits 1 and gh names the missing scope on stderr.
  GitHub: JSON holds authentication keys only. The text table of 'gh ssh-key list' also
          shows signing keys, and then needs the admin:ssh_signing_key scope as well.

EXAMPLES
  forge ssh-key list
  forge ssh-key list --jq '.[].title'
EOF
}

cmd_ssh_key_list() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_host_only
    forge_call ssh_key_list
}

# --- add ---------------------------------------------------------------------------------

help_ssh_key_add() {
    cat <<EOF
NAME
  forge ssh-key add - add a public key to the authenticated user's account

USAGE
  forge ssh-key add <keyfile> --title <text>

DESCRIPTION
  Adds the public key in <keyfile> to the account for SSH authentication. A private key
  file is refused (exit 2).

ARGUMENTS
  <keyfile>           Public key file, e.g. ~/.ssh/id_ed25519.pub, or - for standard input

FLAGS
  -t, --title <text>  Name of the key; required

OUTPUT
  Text: the id of the new key.
  JSON: $SSH_KEY_JSON_SHAPE

PLATFORM NOTES
  GitHub: needs the admin:public_key token scope ('gh auth refresh -s admin:public_key');
          without it the command exits 1. The key is an authentication key, not a signing key.
  GitLab: the key gets GitLab's default usage, authentication and signing.

EXAMPLES
  forge ssh-key add ~/.ssh/id_ed25519.pub --title "work laptop"
EOF
}

cmd_ssh_key_add() {
    arg_keyfile='' opt_title=''
    while [ $# -gt 0 ]; do
        case $1 in
            -t | --title) forge_arg "$@"; opt_title=$2; shift 2 ;;
            -) [ -z "$arg_keyfile" ] || forge_unexpected "$1"; arg_keyfile=$1; shift ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_keyfile" ] || forge_unexpected "$1"; arg_keyfile=$1; shift ;;
        esac
    done
    [ -n "$arg_keyfile" ] || forge_usage_die "<keyfile> is required"
    [ -n "$opt_title" ] || forge_usage_die "--title is required"
    ssh_key_read "$arg_keyfile"
    forge_host_only
    forge_call ssh_key_add
}

# --- delete ------------------------------------------------------------------------------

help_ssh_key_delete() {
    cat <<'EOF'
NAME
  forge ssh-key delete - remove an SSH key from the authenticated user's account

USAGE
  forge ssh-key delete <id>

DESCRIPTION
  Removes the key from the account. Anything that authenticates with it loses access.
  Exits 4 when the account has no key with that id.

ARGUMENTS
  <id>   Key id, from 'forge ssh-key list --json'

OUTPUT
  Text and JSON: nothing; the exit code tells the result.

PLATFORM NOTES
  GitHub: needs the admin:public_key token scope; without it the command exits 1.

EXAMPLES
  forge ssh-key delete 123456
EOF
}

cmd_ssh_key_delete() {
    arg_id=''
    while [ $# -gt 0 ]; do
        case $1 in
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_id" ] || forge_unexpected "$1"; arg_id=$1; shift ;;
        esac
    done
    [ -n "$arg_id" ] || forge_usage_die "<id> is required"
    forge_require_int "<id>" "$arg_id"
    forge_host_only
    forge_call ssh_key_delete "$arg_id"
}
