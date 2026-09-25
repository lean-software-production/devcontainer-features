#!/usr/bin/env bash
# Refresh the committed copies of src/bb and src/tutor under features/.
#
#   .devcontainer/tutor/sync-features.sh           rewrite the copies
#   .devcontainer/tutor/sync-features.sh --check   fail if they are stale (CI)
#
# Dev Containers only accepts local Features beneath .devcontainer/, and its CLI
# (which Codespaces uses) fails to fetch a Feature folder that is a symlink, so
# the Codespace entry point needs real copies. Only files Git would commit are
# copied, so node_modules and dist never land in the copies.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
features=(bb tutor)

copy_features() {
    local out="$1" name
    for name in "${features[@]}"; do
        mkdir -p "$out/$name"
        (
            cd "$repo"
            git ls-files -co --exclude-standard -z -- "src/$name" \
                | while IFS= read -r -d '' file; do [ -e "$file" ] && printf '%s\0' "$file"; done \
                | tar --null -T - -cf -
        ) | tar -C "$out/$name" --strip-components=2 -xf -
    done
}

case "${1:-}" in
    "")
        rm -rf "$here/features"
        copy_features "$here/features"
        echo "synced ${features[*]} into ${here#"$repo"/}/features"
        ;;
    --check)
        scratch="$(mktemp -d)"
        trap 'rm -rf "$scratch"' EXIT
        copy_features "$scratch"
        if ! diff -r "$scratch" "$here/features" >&2; then
            echo "ERROR: ${here#"$repo"/}/features is stale; run .devcontainer/tutor/sync-features.sh and commit the result." >&2
            exit 1
        fi
        echo "${here#"$repo"/}/features matches src/"
        ;;
    *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
