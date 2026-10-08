# shellcheck shell=sh

help_user() {
    cat <<'EOF'
forge user - users of the platform

COMMANDS
  me        The user gh or glab is logged in as

Run 'forge user <command> --help' for details.
EOF
}

help_user_me() {
    cat <<'EOF'
NAME
  forge user me - show the authenticated user

USAGE
  forge user me

DESCRIPTION
  Shows the account gh (GitHub) or glab (GitLab) is logged in as on the repository's host.
  The host comes from the current checkout or --repo.

OUTPUT
  Text: the username.
  JSON: {username, name, email, url}
  name and email are null when the account does not show them; url is the profile page.

PLATFORM NOTES
  GitHub: email is the public profile email, null when it is private.
  GitLab: email is the account's primary email, falling back to the public email.

EXAMPLES
  forge user me
  forge user me --json
  forge user me --jq .email
EOF
}

cmd_user_me() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_call user_me
}
