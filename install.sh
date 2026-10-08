#!/bin/sh
# Installs forge: curl -fsSL https://raw.githubusercontent.com/bifenbecker/forge-cli/main/install.sh | sh
set -eu

FORGE_REPO_SLUG=bifenbecker/forge-cli

usage() {
    cat <<'EOF'
Usage: install.sh [--prefix <dir>] [--version <tag>] [--from <dir>] [--uninstall]

Installs forge into <prefix>/share/forge and a forge command into <prefix>/bin.

  --prefix <dir>    Where to install (default: ~/.local)
  --version <tag>   Release to install, e.g. v0.1.0 (default: the latest release)
  --from <dir>      Install from a local checkout instead of downloading
  --uninstall       Remove forge from <prefix>
  -h, --help        Show this help

Requires: sh, tar, and curl or wget. forge itself needs git, jq, and gh and/or glab.
EOF
}

say() {
    printf 'forge-install: %s\n' "$*"
}

die() {
    printf 'forge-install: %s\n' "$*" >&2
    exit 1
}

prefix=${FORGE_PREFIX:-$HOME/.local}
version=
from=
uninstall=
while [ $# -gt 0 ]; do
    case $1 in
        --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix=$2; shift 2 ;;
        --version) [ $# -ge 2 ] || die "--version needs a value"; version=$2; shift 2 ;;
        --from) [ $# -ge 2 ] || die "--from needs a value"; from=$2; shift 2 ;;
        --uninstall) uninstall=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

home="$prefix/share/forge"
bin="$prefix/bin/forge"

# Only paths that look like a forge installation are removed.
remove_install() {
    if [ -f "$bin" ]; then
        grep -q 'FORGE_HOME' "$bin" 2>/dev/null || die "$bin was not installed by forge; not removing it"
        rm -f "$bin"
        say "removed $bin"
    fi
    if [ -d "$home" ]; then
        [ -f "$home/bin/forge" ] && [ -f "$home/VERSION" ] || die "$home does not look like a forge installation; not removing it"
        rm -rf "$home"
        say "removed $home"
    fi
}

if [ -n "$uninstall" ]; then
    [ -e "$bin" ] || [ -e "$home" ] || die "forge is not installed in $prefix"
    remove_install
    exit 0
fi

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$1"
    else
        die "curl or wget is required"
    fi
}

work=$(mktemp -d 2>/dev/null) || die "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT

if [ -n "$from" ]; then
    [ -f "$from/bin/forge" ] || die "$from is not a forge checkout"
    src=$(CDPATH='' cd -- "$from" && pwd)
else
    command -v tar >/dev/null 2>&1 || die "tar is required"
    if [ -z "$version" ]; then
        version=$(fetch "https://api.github.com/repos/$FORGE_REPO_SLUG/releases/latest" 2>/dev/null |
            sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1) || true
    fi
    if [ -n "$version" ]; then
        url="https://github.com/$FORGE_REPO_SLUG/archive/refs/tags/$version.tar.gz"
    else
        say "no release found; installing the main branch"
        url="https://github.com/$FORGE_REPO_SLUG/archive/refs/heads/main.tar.gz"
    fi
    say "downloading $url"
    fetch "$url" >"$work/forge.tar.gz" || die "download failed: $url"
    tar -xzf "$work/forge.tar.gz" -C "$work" || die "cannot unpack $url"
    src=$(find "$work" -mindepth 2 -maxdepth 2 -type f -name VERSION -exec dirname {} \; | head -n 1)
    [ -n "$src" ] && [ -f "$src/bin/forge" ] || die "the archive does not contain forge"
fi

stage="$work/stage"
mkdir -p "$stage"
for item in bin lib VERSION install.sh LICENSE README.md; do
    [ -e "$src/$item" ] && cp -R "$src/$item" "$stage/"
done

[ ! -e "$home" ] || remove_install
mkdir -p "$prefix/share" "$prefix/bin"
mv "$stage" "$home"

quoted_home=$(printf '%s' "$home" | sed "s/'/'\\\\''/g")
cat >"$bin" <<EOF
#!/bin/sh
FORGE_HOME='$quoted_home'
export FORGE_HOME
exec sh "\$FORGE_HOME/bin/forge" "\$@"
EOF
chmod +x "$bin" "$home/bin/forge"

say "installed forge $(tr -d '\r\n' <"$home/VERSION") into $home"
case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) say "add $prefix/bin to PATH:  export PATH=\"$prefix/bin:\$PATH\"" ;;
esac
for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || say "warning: $tool is not installed; forge needs it"
done
command -v gh >/dev/null 2>&1 || command -v glab >/dev/null 2>&1 ||
    say "warning: neither gh nor glab is installed; forge needs at least one"
