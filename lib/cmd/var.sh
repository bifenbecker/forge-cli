# shellcheck shell=sh
# shellcheck disable=SC2034  # opt_* and arg_* are read by lib/<platform>/var.sh

VAR_JSON_SHAPE='{name, value, scope}
  scope is the environment the variable belongs to, or null for a repository-wide variable.'

help_var() {
    cat <<'EOF'
forge var - CI variables (GitHub Actions variables, GitLab CI/CD variables)

Variables are plain configuration: their values are readable. For credentials use
'forge secret', whose values are never printed.

COMMANDS
  list      List variables
  get       Print the value of one variable
  set       Create or update a variable
  delete    Delete a variable

Run 'forge var <command> --help' for details.
EOF
}

# Names are restricted the same way on both hosts.
var_require_name() {
    case $1 in
        '') forge_usage_die "<name> is required" ;;
        *[!A-Za-z0-9_]*) forge_usage_die "<name> may contain only letters, digits and _, got '$1'" ;;
    esac
}

# --- list --------------------------------------------------------------------------------

help_var_list() {
    cat <<EOF
NAME
  forge var list - list CI variables

USAGE
  forge var list [--env <environment>]

DESCRIPTION
  Lists the CI variables of the repository with their values. Secrets are not included.

FLAGS
  -e, --env <environment>   Only the variables of this deployment environment
                            (GitHub environment / GitLab environment scope)

OUTPUT
  Text: GitHub: the gh table. GitLab: one "NAME<TAB>VALUE<TAB>SCOPE" line per variable,
        with * as the scope of a variable that applies to every environment.
  JSON: array of $VAR_JSON_SHAPE

PLATFORM NOTES
  GitHub: without --env only repository-level variables are listed; environment
          variables appear only with --env.
  GitLab: without --env variables of every environment scope are listed, each with its scope.
  GitLab: masked variables are secrets in forge and are left out; see 'forge secret list'.

EXAMPLES
  forge var list
  forge var list --env production --json
  forge var list --jq '.[].name'
EOF
}

cmd_var_list() {
    opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_call var_list
}

# --- get ---------------------------------------------------------------------------------

help_var_get() {
    cat <<EOF
NAME
  forge var get - print the value of one CI variable

USAGE
  forge var get <name> [--env <environment>]

DESCRIPTION
  Prints the value of a variable. Exits 4 when no such variable exists.

ARGUMENTS
  <name>                    Variable name: letters, digits and _

FLAGS
  -e, --env <environment>   The variable of this environment; default: the repository-wide one

OUTPUT
  Text: the value.
  JSON: $VAR_JSON_SHAPE

PLATFORM NOTES
  GitLab: without --env the variable with environment scope * is read.
  GitLab: a masked variable is a secret in forge; asking for it exits 4.

EXAMPLES
  forge var get DEPLOY_REGION
  forge var get DEPLOY_REGION --env staging --json
EOF
}

cmd_var_get() {
    arg_name='' opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    var_require_name "$arg_name"
    forge_call var_get "$arg_name"
}

# --- set ---------------------------------------------------------------------------------

help_var_set() {
    cat <<EOF
NAME
  forge var set - create or update a CI variable

USAGE
  forge var set <name> (--body <value> | --body-file <path|->) [--env <environment>]

DESCRIPTION
  Sets the variable to the value, creating it when it does not exist. The value is passed to
  the host on standard input, not on a command line. Trailing newlines of a file are dropped.

ARGUMENTS
  <name>                    Variable name: letters, digits and _

FLAGS
  -b, --body <value>        The value (alias: --value)
  -F, --body-file <path|->  Read the value from a file, or - for standard input
  -e, --env <environment>   Set it for this environment; default: repository-wide

OUTPUT
  Text: nothing.
  JSON: the variable after the change, $VAR_JSON_SHAPE

PLATFORM NOTES
  GitHub: --env needs an existing environment.
  GitLab: --env sets the environment scope; a new variable is created unmasked, unprotected
          and raw. An existing variable keeps its flags.
  GitLab: a masked variable is a secret in forge; setting one exits 1. Use 'forge secret set'.

EXAMPLES
  forge var set DEPLOY_REGION --body eu-west-1
  forge var set DEPLOY_REGION --env staging --value us-east-1 --json
  printf '%s' "\$CONFIG" | forge var set APP_CONFIG --body-file -
EOF
}

cmd_var_set() {
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
    var_require_name "$arg_name"
    forge_require_body value
    forge_call var_set "$arg_name"
}

# --- delete ------------------------------------------------------------------------------

help_var_delete() {
    cat <<'EOF'
NAME
  forge var delete - delete a CI variable

USAGE
  forge var delete <name> [--env <environment>]

DESCRIPTION
  Deletes the variable. Exits 4 when it does not exist.

ARGUMENTS
  <name>                    Variable name

FLAGS
  -e, --env <environment>   Delete the variable of this environment; default: repository-wide

OUTPUT
  Text and JSON: nothing; the exit code tells the result.

PLATFORM NOTES
  GitLab: without --env the variable with environment scope * is deleted.
  GitLab: a masked variable is a secret in forge; deleting it here exits 4.

EXAMPLES
  forge var delete DEPLOY_REGION
  forge var delete DEPLOY_REGION --env staging
EOF
}

cmd_var_delete() {
    arg_name='' opt_env=''
    while [ $# -gt 0 ]; do
        case $1 in
            -e | --env) forge_arg "$@"; opt_env=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) [ -z "$arg_name" ] || forge_unexpected "$1"; arg_name=$1; shift ;;
        esac
    done
    var_require_name "$arg_name"
    forge_call var_delete "$arg_name"
}
