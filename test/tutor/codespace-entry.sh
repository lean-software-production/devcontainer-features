#!/usr/bin/env bash
# Brings up the Codespace entry point (.devcontainer/tutor) with the devcontainer
# CLI, exactly as committed except for what only GitHub Codespaces provides: a
# user-writable /workspaces, and a port that cannot collide with a BB the
# developer runs on the host. Needs docker, the devcontainer CLI and network.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
devcontainer="${DEVCONTAINER:-devcontainer}"
label="tutor.codespace-entry-test=$$"
workspace="$(mktemp -d)"
cleanup() {
    local id
    id="$(docker ps -aq --filter "label=$label")"
    [ -z "$id" ] || docker rm -f "$id" >/dev/null
    rm -rf "$workspace"
}
trap cleanup EXIT

mkdir -p "$workspace/.devcontainer"
cp -R "$repo_root/.devcontainer/tutor/features" "$workspace/.devcontainer/features"
node - "$repo_root/.devcontainer/tutor/devcontainer.json" > "$workspace/.devcontainer/devcontainer.json" <<'JS'
const fs = require("fs");
// The entry point uses only whole-line // comments.
const text = fs.readFileSync(process.argv[2], "utf8").split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n");
const config = JSON.parse(text);
const bb = config.features["./features/bb"];
const tutor = config.features["./features/tutor"];
Object.assign(bb, { serverPort: "48886", hostDaemonPort: "48887", dataDir: "/home/node/.bb-state" });
Object.assign(tutor, {
  course: tutor.course.replace(/^\/workspaces\//, "/home/node/"),
  factory: tutor.factory.replace(/^\/workspaces\//, "/home/node/"),
});
config.forwardPorts = [];
delete config.portsAttributes;
process.stdout.write(JSON.stringify(config, null, 2) + "\n");
JS

"$devcontainer" up --workspace-folder "$workspace" --id-label "$label" > "$workspace/up.json" 2> "$workspace/up.log" || {
    tail -n 60 "$workspace/up.log" >&2
    echo "devcontainer up failed for the Codespace entry point" >&2
    exit 1
}
grep -q '"outcome":"success"' "$workspace/up.json" || { cat "$workspace/up.json" >&2; exit 1; }

in_container() {
    "$devcontainer" exec --workspace-folder "$workspace" --id-label "$label" \
        env BB_SERVER_URL=http://127.0.0.1:48886 BB_HOST_DAEMON_PORT=48887 BB_DATA_DIR=/home/node/.bb-state "$@"
}
in_container bb-feature-status
in_container git -C /home/node/tutorial rev-parse --verify HEAD >/dev/null
in_container bash -c 'bb plugin list --json | node -e "
let s = \"\"; process.stdin.on(\"data\", (d) => (s += d)).on(\"end\", () => {
  const p = JSON.parse(s).plugins.find((x) => x.id === \"tutor\");
  if (!p || p.status !== \"running\") { console.error(\"tutor plugin is not running:\", p); process.exit(1); }
});"'
in_container bash -c 'bb settings ui get sidebar.threadListProvider --json | grep -q "\"tutor/course-rail\""'
echo 'Codespace entry point came up with Tutor running'
