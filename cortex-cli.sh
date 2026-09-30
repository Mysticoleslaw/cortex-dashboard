#!/bin/bash
# Cortex — Claude Code Dashboard
# `cortex` command: update, roll back, or switch between released versions.
#
#   cortex update          install the latest release
#   cortex rollback        go back to the release before the installed one
#   cortex use <version>   install a specific release (e.g. v1.2.0)
#   cortex version         show installed version and whether an update exists
#   cortex versions        list available releases

REPO_URL="${CORTEX_REPO_URL:-https://github.com/Mysticoleslaw/cortex-dashboard}"
SRC_DIR="${CORTEX_DIR:-$HOME/.cortex-dashboard}"
VERSION_FILE="$HOME/.claude/cortex-version"

die() { echo "cortex: $*" >&2; exit 1; }

installed_version() { cat "$VERSION_FILE" 2>/dev/null || echo "unknown"; }

# True when release tag $1 is newer than $2 (both vX.Y.Z)
is_newer() {
    [[ "$1" =~ ^v[0-9] && "$2" =~ ^v[0-9] && "$1" != "$2" ]] \
        && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

# Release tags (vX.Y.Z), oldest → newest
list_versions() {
    if command -v git > /dev/null 2>&1; then
        git ls-remote --tags --refs "$REPO_URL" 'v*' 2>/dev/null | sed 's|.*refs/tags/||'
    else
        local api="${REPO_URL/github.com/api.github.com/repos}/tags?per_page=100"
        curl -fsSL "$api" 2>/dev/null | jq -r '.[].name | select(startswith("v"))'
    fi | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V
}

latest_version() { list_versions | tail -n 1; }

# Download <ref> into SRC_DIR (fresh copy, swapped in only on success) and install it
install_ref() {
    local ref="$1" tmp
    tmp=$(mktemp -d) || die "can't create a temp directory"
    if command -v git > /dev/null 2>&1; then
        git clone --quiet --depth 1 --branch "$ref" "$REPO_URL" "$tmp/src" 2>/dev/null \
            || { rm -rf "$tmp"; die "couldn't download $ref"; }
    else
        mkdir -p "$tmp/src"
        curl -fsSL "$REPO_URL/archive/$ref.tar.gz" | tar -xz -C "$tmp/src" --strip-components 1 \
            || { rm -rf "$tmp"; die "couldn't download $ref"; }
    fi
    rm -rf "$SRC_DIR" && mv "$tmp/src" "$SRC_DIR" && rm -rf "$tmp"
    bash "$SRC_DIR/install.sh" > /dev/null || die "install.sh failed for $ref"
    echo "$ref" > "$VERSION_FILE"
    # Clear the cached update check so the dashboard banner updates right away
    rm -f "${CORTEX_CACHE_DIR:-/tmp}/claude-statusline-update"
    echo "Cortex $ref installed. Changes appear on the next statusline refresh."
}

cmd_update() {
    local latest current
    latest=$(latest_version); [ -n "$latest" ] || die "couldn't reach $REPO_URL to check for releases"
    current=$(installed_version)
    if [ "$current" = "$latest" ]; then
        echo "Cortex is up to date ($current)."
    elif is_newer "$current" "$latest"; then
        # Never downgrade on "update" — that's what rollback / use are for
        echo "Cortex $current is newer than the latest release ($latest); nothing to update."
    else
        echo "Updating Cortex: $current → $latest"
        install_ref "$latest"
    fi
}

cmd_rollback() {
    local current prev
    current=$(installed_version)
    [[ "$current" =~ ^v[0-9] ]] || die "installed version ($current) isn't a release; use 'cortex use <version>'"
    prev=$(list_versions | awk -v cur="$current" '$0 == cur { print last; found = 1; exit } { last = $0 } END { if (!found) exit 1 }')
    [ -n "$prev" ] || die "no release older than $current"
    echo "Rolling back Cortex: $current → $prev"
    install_ref "$prev"
}

cmd_use() {
    local want="$1"
    [ -n "$want" ] || die "usage: cortex use <version>   (see 'cortex versions')"
    [[ "$want" == v* ]] || want="v$want"
    list_versions | grep -qx "$want" || die "no release named $want (see 'cortex versions')"
    install_ref "$want"
}

cmd_version() {
    local current latest
    current=$(installed_version)
    latest=$(latest_version)
    echo "Installed: $current"
    if [ -z "$latest" ]; then echo "Latest:    (couldn't check)"
    elif [ "$current" = "$latest" ]; then echo "Latest:    $latest — up to date"
    elif is_newer "$current" "$latest"; then echo "Latest:    $latest — you're ahead of the latest release"
    else echo "Latest:    $latest — run 'cortex update'"; fi
}

cmd_versions() {
    local current versions
    current=$(installed_version)
    versions=$(list_versions); [ -n "$versions" ] || die "couldn't reach $REPO_URL to list releases"
    printf '%s\n' "$versions" | sort -rV | while read -r v; do
        if [ "$v" = "$current" ]; then echo "* $v (installed)"; else echo "  $v"; fi
    done
}

usage() { sed -n '4,9p' "$0" | sed 's/^# //'; }

# Everything runs from main(), so install.sh replacing this file mid-run is safe
main() {
    case "${1:-}" in
        update)      cmd_update ;;
        rollback)    cmd_rollback ;;
        use)         cmd_use "${2:-}" ;;
        version|-v)  cmd_version ;;
        versions)    cmd_versions ;;
        ""|help|-h|--help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"; exit
