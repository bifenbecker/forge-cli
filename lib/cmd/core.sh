# shellcheck shell=sh

help_root() {
    cat <<'EOF'
forge - one command line for GitHub and GitLab

USAGE
  forge <command> [<subcommand>...] [<args>] [flags]

DESCRIPTION
  forge wraps gh (GitHub) and glab (GitLab) behind one set of commands, flags and JSON shapes.
  The platform is detected from the git remote, so the same call works in either kind of
  repository. Every command takes --help; --json prints a normalised shape that is the same
  on both platforms.

COMMANDS
  request      Pull requests (GitHub) and merge requests (GitLab); aliases: pr, mr
  issue        Issues
  ci           CI runs (workflow runs / pipelines), jobs, logs and artifacts
  release      Releases and their assets
  repo         Repository info, clone, fork, links
  label        Repository labels
  milestone    Milestones
  branch       Remote branches and their protection
  tag          Remote tags
  var          CI variables
  secret       CI secrets
  deploy-key   Repository deploy keys
  ssh-key      SSH keys of the current user
  user         The authenticated user
  auth         Authentication status
  api          Raw call to the platform API (gh api / glab api)

  detect       Print the platform: github or gitlab
  doctor       Check tools, authentication and detection
  version      Print the forge version
  self         Update or uninstall forge

GLOBAL FLAGS
  -R, --repo <[HOST/]PATH>  Act on this repository instead of the current checkout
  --json                    Print normalised JSON (see each command's OUTPUT)
  --jq <expr>               Filter that JSON with a jq expression (implies --json)
  -h, --help                Help for any command: forge request view --help
  -V, --version             Print the forge version

ENVIRONMENT
  FORGE_PLATFORM   github | gitlab; skips detection
  FORGE_REMOTE     git remote to read the repository from (default: origin)
  git config forge.platform / forge.remote set the same per repository.

EXIT CODES
  0 success, 1 failure, 2 wrong usage, 3 not supported on this platform, 4 not found

EXAMPLES
  forge request list --state open --json
  forge request view 42 --jq '.state'
  forge ci run list --limit 5
  forge release view v1.2.0 --json
EOF
}

help_version() {
    cat <<'EOF'
NAME
  forge version - print the forge version

USAGE
  forge version
  forge --version

DESCRIPTION
  Prints the installed forge version, read from the VERSION file of the installation.

OUTPUT
  Text: the version, e.g. 0.1.0
  JSON: {"version": "0.1.0"}

EXAMPLES
  forge --version
  forge version --json
EOF
}

cmd_version() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_version=$(tr -d '\r\n' <"$FORGE_HOME/VERSION")
    if forge_json_mode; then
        forge_require jq
        _jq -n --arg v "$forge_version" '{version: $v}' | forge_emit '.'
    else
        printf '%s\n' "$forge_version"
    fi
}

help_detect() {
    cat <<'EOF'
NAME
  forge detect - print which platform hosts the repository

USAGE
  forge detect

DESCRIPTION
  Resolves the platform, host and repository path the same way every other command does:
  FORGE_PLATFORM, then git config forge.platform, then the remote host (github.com, gitlab.com,
  gitlab.*), then which of gh / glab is logged in to that host.

OUTPUT
  Text: github or gitlab
  JSON: {"platform": "github", "host": "github.com", "repo": "owner/repo"}

EXAMPLES
  forge detect
  forge detect --json
  forge --repo gitlab.example.com/group/project detect --json
EOF
}

cmd_detect() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_resolve_repo
    if forge_json_mode; then
        forge_require jq
        _jq -n --arg p "$FORGE_PLATFORM" --arg h "$FORGE_HOST" --arg r "$FORGE_REPO_PATH" \
            '{platform: $p, host: $h, repo: $r}' | forge_emit '.'
    else
        printf '%s\n' "$FORGE_PLATFORM"
    fi
}

help_doctor() {
    cat <<'EOF'
NAME
  forge doctor - check that forge can work here

USAGE
  forge doctor

DESCRIPTION
  Reports the forge version, the tools forge depends on (git, jq, gh, glab), the detected
  platform and repository, and whether the platform CLI is authenticated for that host.
  Exits 1 when something required is missing.

OUTPUT
  Text: one line per check, marked ok or missing.
  JSON: {"version", "platform", "host", "repo", "authenticated",
         "tools": {"git", "jq", "gh", "glab"}}  (tool values are versions or null)

EXAMPLES
  forge doctor
  forge doctor --json
EOF
}

forge_tool_version() {
    command -v "$1" >/dev/null 2>&1 || return 0
    case $1 in
        git) git --version | sed 's/^git version //' ;;
        jq) jq --version | sed 's/^jq-//' ;;
        gh) gh --version | sed -n '1s/^gh version \([^ ]*\).*/\1/p' ;;
        glab) glab --version | sed -n '1s/^glab \(version \)\{0,1\}\([^ ]*\).*/\2/p' ;;
    esac
}

cmd_doctor() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    doctor_ok=1
    doctor_git=$(forge_tool_version git | tr -d '\r')
    doctor_jq=$(forge_tool_version jq | tr -d '\r')
    doctor_gh=$(forge_tool_version gh | tr -d '\r')
    doctor_glab=$(forge_tool_version glab | tr -d '\r')
    doctor_platform=''
    doctor_auth=false
    if (forge_resolve_repo) >/dev/null 2>&1; then
        forge_resolve_repo
        doctor_platform=$FORGE_PLATFORM
        case $FORGE_PLATFORM in
            github) [ -n "$doctor_gh" ] && gh auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && doctor_auth=true ;;
            gitlab) [ -n "$doctor_glab" ] && glab auth status --hostname "$FORGE_HOST" >/dev/null 2>&1 && doctor_auth=true ;;
        esac
    fi
    [ -n "$doctor_git" ] && [ -n "$doctor_jq" ] || doctor_ok=
    [ -n "$doctor_gh" ] || [ -n "$doctor_glab" ] || doctor_ok=
    [ -z "$doctor_platform" ] || [ "$doctor_auth" = true ] || doctor_ok=

    if forge_json_mode && [ -n "$doctor_jq" ]; then
        _jq -n --arg v "$(tr -d '\r\n' <"$FORGE_HOME/VERSION")" --arg p "$doctor_platform" \
            --arg h "${FORGE_HOST:-}" --arg r "${FORGE_REPO_PATH:-}" --argjson a "$doctor_auth" \
            --arg git "$doctor_git" --arg jq "$doctor_jq" --arg gh "$doctor_gh" --arg glab "$doctor_glab" \
            'def n: if . == "" then null else . end;
             {version: $v, platform: ($p | n), host: ($h | n), repo: ($r | n), authenticated: $a,
              tools: {git: ($git | n), jq: ($jq | n), gh: ($gh | n), glab: ($glab | n)}}' |
            forge_emit '.'
    else
        printf 'forge     %s\n' "$(tr -d '\r\n' <"$FORGE_HOME/VERSION")"
        for doctor_tool in git jq gh glab; do
            eval "doctor_value=\$doctor_$doctor_tool"
            printf '%-9s %s\n' "$doctor_tool" "${doctor_value:-missing}"
        done
        if [ -n "$doctor_platform" ]; then
            printf 'platform  %s (%s/%s)\n' "$doctor_platform" "$FORGE_HOST" "$FORGE_REPO_PATH"
            if [ "$doctor_auth" = true ]; then
                printf 'auth      ok\n'
            else
                printf 'auth      not logged in to %s\n' "$FORGE_HOST"
            fi
        else
            printf 'platform  not detected (no git remote, or unknown host)\n'
        fi
    fi
    [ -n "$doctor_ok" ] || exit 1
}

help_self() {
    cat <<'EOF'
forge self - manage the forge installation

COMMANDS
  update       Install the latest release over this installation
  uninstall    Remove forge from this machine

Run 'forge self <command> --help' for details.
EOF
}

help_self_update() {
    cat <<'EOF'
NAME
  forge self update - install the latest forge over this installation

USAGE
  forge self update [--version <tag>]

DESCRIPTION
  Downloads forge from GitHub and installs it into the same prefix, using the installer that
  came with this installation.

FLAGS
  --version <tag>   Install this release instead of the latest, e.g. v0.2.0

OUTPUT
  Text: the installer's progress and the installed version.

EXAMPLES
  forge self update
  forge self update --version v0.1.0
EOF
}

forge_installer() {
    [ -f "$FORGE_HOME/install.sh" ] || forge_die "no installer at $FORGE_HOME/install.sh: this copy was not installed with install.sh"
    forge_installer_prefix=$(CDPATH='' cd -- "$FORGE_HOME/../.." && pwd)
}

cmd_self_update() {
    self_version=''
    while [ $# -gt 0 ]; do
        case $1 in
            --version) forge_arg "$@"; self_version=$2; shift 2 ;;
            -*) forge_unknown_flag "$1" ;;
            *) forge_unexpected "$1" ;;
        esac
    done
    forge_installer
    sh "$FORGE_HOME/install.sh" --prefix "$forge_installer_prefix" ${self_version:+--version "$self_version"}
}

help_self_uninstall() {
    cat <<'EOF'
NAME
  forge self uninstall - remove forge from this machine

USAGE
  forge self uninstall

DESCRIPTION
  Removes the forge command and its library directory from the prefix it was installed into.
  Nothing outside that installation is touched.

OUTPUT
  Text: what was removed.

EXAMPLES
  forge self uninstall
EOF
}

cmd_self_uninstall() {
    [ $# -eq 0 ] || forge_unexpected "$1"
    forge_installer
    sh "$FORGE_HOME/install.sh" --prefix "$forge_installer_prefix" --uninstall
}
