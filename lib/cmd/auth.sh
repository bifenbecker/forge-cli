# shellcheck shell=sh

help_auth() {
    cat <<'EOF'
forge auth - authentication of gh and glab

forge does not log in by itself; it uses the login of gh (GitHub) or glab (GitLab).
To log in run 'gh auth login' or 'glab auth login'.

COMMANDS
  status    Whether gh or glab is logged in for the repository's host

Run 'forge auth <command> --help' for details.
EOF
}

help_auth_status() {
    cat <<'EOF'
NAME
  forge auth status - check whether gh or glab is logged in for the host

USAGE
  forge auth status

DESCRIPTION
  Checks the login of the platform CLI for the host of the current checkout (or --repo).
  Exits 1 when it is not authenticated, so it can guard a script.

OUTPUT
  Text: the platform CLI's status report (tokens are not shown).
  JSON: {platform, host, authenticated, user}
  authenticated is true or false; user is the username, or null when not authenticated.
  The JSON is printed whether or not the CLI is logged in; the exit code is 0 or 1. When the
  state cannot be told (the host is unreachable, the CLI fails), no JSON is printed: the
  CLI's error goes to stderr and the exit code is 1.

PLATFORM NOTES
  GitHub: authenticated means the active account for the host has a working token; false
          means gh has no account for the host. An account whose token check fails (an
          invalid token or a network error, which gh does not tell apart) prints no JSON.
  GitLab: authenticated means the API answers as a user; a GITLAB_TOKEN in the environment
          counts as a login. false means the API answered 401 or glab has no token.

EXAMPLES
  forge auth status
  forge auth status --json
  forge auth status --jq .user
EOF
}

cmd_auth_status() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_host_only
    forge_call auth_status
}
