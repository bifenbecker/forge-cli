# shellcheck shell=sh

# Command help is NAME, USAGE, DESCRIPTION, [ARGUMENTS], [FLAGS], OUTPUT, [PLATFORM NOTES],
# EXAMPLES, written by the command. EXIT CODES and GLOBAL FLAGS are appended here.
FORGE_HELP_SECTIONS='NAME USAGE DESCRIPTION OUTPUT EXAMPLES'

forge_show_help() {
    "help_$1"
    if forge_fn_exists "cmd_$1"; then
        cat <<'EOF'

EXIT CODES
  0  success
  1  the host or a tool failed
  2  wrong usage: unknown flag, missing argument
  3  not supported on this platform
  4  not found

GLOBAL FLAGS
  -R, --repo <[HOST/]PATH>  Act on this repository instead of the current checkout
  --json                    Print the normalised JSON described under OUTPUT
  --jq <expr>               Filter that JSON with a jq expression (implies --json)
  -h, --help                Show this help
EOF
    fi
}
