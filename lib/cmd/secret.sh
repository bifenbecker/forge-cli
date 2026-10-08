# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/secret.sh

help_secret() {
    cat <<'EOF'
forge secret - CI secrets (GitHub Actions secrets, masked GitLab CI/CD variables)

Secret values are write-only: forge never prints them, and passes them to gh and glab on
standard input rather than on a command line.

COMMANDS
  list      List secret names
  set       Create or update a secret
  delete    Delete a secret

Run 'forge secret <command> --help' for details.
EOF
}

secret_require_name() {
    case $1 in
        '') forge_usage_die "<name> is required" ;;
        *[!A-Za-z0-9_]*) forge_usage_die "<name> may contain only letters, digits and _, got '$1'" ;;
    esac
}

# --- list --------------------------------------------------------------------------------

help_secret_list() {
    cat <<'EOF'
NAME
  forge secret list - list CI secret names

USAGE
  forge secret list [--env <environment>]

DESCRIPTION
  Lists the names of the repository's CI secrets. Values are never shown.

FLAGS
  -e, --env <environment>   Only the secrets of this deployment environment
                            (GitHub environment / GitLab environment scope)

OUTPUT
  Text: GitHub: the gh table. GitLab: one name per line.
  JSON: array of {name, updated_at}
  updated_at is an ISO 8601 time, or null where the host does not record it.

PLATFORM NOTES
  GitHub: without --env only repository-level secrets are listed.
  GitLab: a secret is a CI/CD variable with masked=true. Without --env, masked variables of
          every environment scope are listed. updated_at is always null: GitLab keeps no
          timestamp for variables.

EXAMPLES
  forge secret list
  forge secret list --env production --json
  forge secret list --jq '.[].name'
EOF
}

cmd_secret_list() {
    opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_call secret_list
}

# --- set ---------------------------------------------------------------------------------

help_secret_set() {
    cat <<'EOF'
NAME
  forge secret set - create or update a CI secret

USAGE
  forge secret set <name> (--body-file <path|-> | --body <value>) [--env <environment>]

DESCRIPTION
  Stores the secret, creating it when it does not exist. The value is never echoed. Prefer
  --body-file: a --body value is visible to other processes on this machine while forge runs.
  Trailing newlines of a file are dropped.

ARGUMENTS
  <name>                    Secret name: letters, digits and _

FLAGS
  -F, --body-file <path|->  Read the value from a file, or - for standard input
  -b, --body <value>        The value on the command line (alias: --value)
  -e, --env <environment>   Set it for this environment; default: repository-wide

OUTPUT
  Text: nothing.
  JSON: {name, updated_at}  (never the value)

PLATFORM NOTES
  GitHub: --env needs an existing environment.
  GitLab: a new secret is created as a variable with masked and hidden set (hidden needs
          GitLab 17.4 or later; older versions only mask it). GitLab rejects a masked value
          shorter than 8 characters or spanning several lines (exit 1).
  GitLab: setting a name that exists as a plain variable exits 1; delete it with
          'forge var delete' first.

EXAMPLES
  forge secret set DEPLOY_TOKEN --body-file - < token.txt
  printf '%s' "$TOKEN" | forge secret set DEPLOY_TOKEN --body-file - --env production
EOF
}

cmd_secret_set() {
    arg_name='' opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -b | --body | --value) forge_arg "$@"; FORGE_BODY=$2; FORGE_BODY_SET=1; shift 2 ;;
            -F | --body-file) forge_arg "$@"; forge_read_body_file "$2"; shift 2 ;;
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    secret_require_name "$arg_name"
    forge_require_body "secret value"
    forge_call secret_set "$arg_name"
}

# --- delete ------------------------------------------------------------------------------

help_secret_delete() {
    cat <<'EOF'
NAME
  forge secret delete - delete a CI secret

USAGE
  forge secret delete <name> [--env <environment>]

DESCRIPTION
  Deletes the secret. Exits 4 when it does not exist.

ARGUMENTS
  <name>                    Secret name

FLAGS
  -e, --env <environment>   Delete the secret of this environment; default: repository-wide

OUTPUT
  Text and JSON: nothing; the exit code tells the result.

PLATFORM NOTES
  GitLab: deletes the masked variable of that name in scope --env, or * without it. A plain
          (unmasked) variable is not a secret: deleting it here exits 4.

EXAMPLES
  forge secret delete DEPLOY_TOKEN
  forge secret delete DEPLOY_TOKEN --env production
EOF
}

cmd_secret_delete() {
    arg_name='' opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    secret_require_name "$arg_name"
    forge_call secret_delete "$arg_name"
}
