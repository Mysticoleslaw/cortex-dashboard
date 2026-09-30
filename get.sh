#!/bin/bash
# Cortex — Claude Code Dashboard
# One-line installer:
#
#   curl -fsSL https://raw.githubusercontent.com/Mysticoleslaw/cortex-dashboard/Main/get.sh | bash
#
# Installs the latest release into ~/.cortex-dashboard (override with CORTEX_DIR)
# and runs install.sh. CORTEX_REF picks a specific version, branch, or tag.
# After installing, use the `cortex` command to update or roll back.

# Everything runs inside main(), called on the last line, so a download that
# cuts off partway never executes a partial script.
main() {
    set -euo pipefail

    local repo_url="${CORTEX_REPO_URL:-https://github.com/Mysticoleslaw/cortex-dashboard}"
    local dest="${CORTEX_DIR:-$HOME/.cortex-dashboard}"
    local ref="${CORTEX_REF:-}"

    for dep in jq python3 curl; do
        if ! command -v "$dep" > /dev/null 2>&1; then
            echo "Error: $dep is required. Install it (e.g. brew install $dep) and re-run." >&2
            exit 1
        fi
    done

    # Default to the latest release (vX.Y.Z tag); fall back to Main if none exist
    if [ -z "$ref" ]; then
        if command -v git > /dev/null 2>&1; then
            ref=$(git ls-remote --tags --refs "$repo_url" 'v*' | sed 's|.*refs/tags/||' \
                | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)
        else
            ref=$(curl -fsSL "${repo_url/github.com/api.github.com/repos}/releases/latest" \
                | jq -r '.tag_name // empty' || true)
        fi
        ref="${ref:-Main}"
    fi

    echo "── Fetching Cortex $ref ──"
    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    if command -v git > /dev/null 2>&1; then
        git clone --quiet --depth 1 --branch "$ref" "$repo_url" "$tmp/src"
    else
        mkdir -p "$tmp/src"
        curl -fsSL "$repo_url/archive/$ref.tar.gz" | tar -xz -C "$tmp/src" --strip-components 1
    fi
    rm -rf "$dest"
    mv "$tmp/src" "$dest"
    rm -rf "$tmp"
    trap - EXIT  # $tmp is local to main(); don't let the trap run after it's gone

    bash "$dest/install.sh"
    echo "$ref" > "$HOME/.claude/cortex-version"
    echo ""
    echo "Installed Cortex $ref. Update later with: cortex update"
}

main "$@"
