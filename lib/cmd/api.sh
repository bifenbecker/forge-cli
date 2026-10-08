# shellcheck shell=sh
# shellcheck disable=SC2034  # arg_* are read by lib/<platform>/api.sh

help_api() {
    cat <<'EOF'
NAME
  forge api - raw call to the platform API (gh api / glab api)

USAGE
  forge api <endpoint> [<native flags>...]

DESCRIPTION
  Runs 'gh api --hostname <host> <endpoint> ...' on GitHub or
  'glab api --hostname <host> <endpoint> ...' on GitLab, with the host of the repository.
  Everything after <endpoint> is passed to gh or glab unchanged. This is the escape hatch for
  what no forge command covers: endpoints, flags and response shapes are those of the
  platform, NOT normalised. A script that must run on both hosts needs one call per platform
  (see 'forge detect').

  {repo} in <endpoint> is replaced by the repository's API prefix, so one string addresses
  the repository on either host:
    GitHub: repos/OWNER/REPO
    GitLab: projects/<url-encoded path>, e.g. projects/group%2Fproject
  On GitHub the gh-style repos/{owner}/{repo} is accepted too and means the same.

ARGUMENTS
  <endpoint>         API path without the version prefix, e.g. {repo}/branches, user,
                     or graphql
  <native flags>     Flags of 'gh api' or 'glab api': -X/--method, -f/--raw-field,
                     -F/--field, -H/--header, --input, --paginate, -i/--include, ...

OUTPUT
  Text: the platform's response body as gh or glab prints it.
  JSON: with --json or --jq, the response is read as JSON and passed through forge's jq:
        --jq filters it the same way on both platforms. The shape is the platform's own.

PLATFORM NOTES
  forge reads -R/--repo, --json, --jq and -h/--help itself, before gh or glab sees them:
  pass -R to pick the repository, and --jq to filter. To hand such a flag to gh or glab
  anyway, put it after a lone --, e.g. forge api {repo} -- --jq .name.
  A flag written --name=value reaches gh or glab as two arguments, --name value.
  GitHub: gh also fills its own {owner}, {repo} and {branch} placeholders; forge points them
          at the --repo repository.
  GitLab: glab fills :fullpath, :id, :branch and similar placeholders from the current
          directory only, not from --repo; prefer {repo}.

EXAMPLES
  forge api {repo}
  forge api {repo}/branches --paginate --jq '.[].name'
  forge api user --jq .login
  forge api {repo}/issues -X POST -f title="from forge"
EOF
}

# Replaces every occurrence of $2 in $1 with $3.
api_replace() {
    api_rp_in=$1
    api_rp_out=''
    while :; do
        case $api_rp_in in
            *"$2"*)
                api_rp_out=$api_rp_out${api_rp_in%%"$2"*}$3
                api_rp_in=${api_rp_in#*"$2"}
                ;;
            *) break ;;
        esac
    done
    printf '%s' "$api_rp_out$api_rp_in"
}

cmd_api() {
    [ $# -gt 0 ] || forge_usage_die "<endpoint> is required"
    arg_endpoint=$1
    shift
    case $arg_endpoint in
        -*) forge_usage_die "<endpoint> comes first, got the flag '$arg_endpoint'" ;;
    esac
    forge_host_only
    forge_call api_call "$@"
}
