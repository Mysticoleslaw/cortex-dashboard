#!/bin/bash
# Cortex — Claude Code Dashboard
# One-line installer / updater:
#
#   curl -fsSL https://raw.githubusercontent.com/Mysticoleslaw/cortex-dashboard/Main/get.sh | bash
#
# Downloads Cortex into ~/.cortex-dashboard (override with CORTEX_DIR) and runs
# install.sh. Re-run the same command to update. CORTEX_REF picks a branch or
# tag (default: Main).

# Everything runs inside main(), called on the last line, so a download that
# cuts off partway never executes a partial script.
main() {
    set -euo pipefail

    local repo_url="${CORTEX_REPO_URL:-https://github.com/Mysticoleslaw/cortex-dashboard}"
    local dest="${CORTEX_DIR:-$HOME/.cortex-dashboard}"
    local ref="${CORTEX_REF:-Main}"

    echo "── Fetching Cortex ($ref) ──"

    for dep in jq python3; do
        if ! command -v "$dep" > /dev/null 2>&1; then
            echo "Error: $dep is required. Install it (e.g. brew install $dep) and re-run." >&2
            exit 1
        fi
    done

    if command -v git > /dev/null 2>&1; then
        if [ -d "$dest/.git" ]; then
            git -C "$dest" fetch --quiet --depth 1 origin "$ref"
            git -C "$dest" checkout --quiet --force FETCH_HEAD
        else
            rm -rf "$dest"
            git clone --quiet --depth 1 --branch "$ref" "$repo_url" "$dest"
        fi
    else
        # No git: download a tarball of the ref instead
        local tmp
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL "$repo_url/archive/$ref.tar.gz" | tar -xz -C "$tmp" --strip-components 1
        rm -rf "$dest"
        mv "$tmp" "$dest"
        trap - EXIT
    fi

    bash "$dest/install.sh"
    echo "Source kept at $dest — re-run the one-liner to update."
}

main "$@"
