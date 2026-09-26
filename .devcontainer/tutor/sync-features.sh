#!/usr/bin/env bash
# Refresh the committed copies of this repository's Features under features/:
# every "./features/<id>" that devcontainer.json uses is a copy of src/<id>.
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
# The entry point uses only whole-line // comments, like codespace-entry.sh assumes.
mapfile -t features < <(node - "$here/devcontainer.json" <<'JS'
const fs = require("fs");
const text = fs.readFileSync(process.argv[2], "utf8").split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n");
for (const ref of Object.keys(JSON.parse(text).features || {})) {
  const m = /^\.\/features\/([a-z0-9-]+)$/.exec(ref);
  if (!m) throw new Error(`unexpected Feature reference ${ref}; only ./features/<id> copies of src/<id> are synced`);
  console.log(m[1]);
}
JS
)
[ "${#features[@]}" -gt 0 ] || { echo "ERROR: no ./features/<id> references in devcontainer.json" >&2; exit 1; }
for name in "${features[@]}"; do
    [ -f "$repo/src/$name/devcontainer-feature.json" ] || { echo "ERROR: devcontainer.json uses ./features/$name but src/$name is not a Feature" >&2; exit 1; }
done

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
