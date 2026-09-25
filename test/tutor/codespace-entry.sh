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
# Each check names itself; a failure shows the Tutor start-up log.
check() {
    local what="$1"; shift
    if "$@"; then echo "ok   $what"; return 0; fi
    echo "FAIL $what" >&2
    in_container cat /home/node/.bb-state/.tutor-feature/autostart.log >&2 || true
    exit 1
}
check "bb is running" in_container bb-feature-status
check "the course was cloned" in_container git -C /home/node/tutorial rev-parse --verify HEAD
check "the Tutor plugin is running" in_container bash -c 'bb plugin list --json | node -e "
let s = \"\"; process.stdin.on(\"data\", (d) => (s += d)).on(\"end\", () => {
  const p = JSON.parse(s).plugins.find((x) => x.id === \"tutor\");
  if (!p || p.status !== \"running\") { console.error(\"tutor plugin is not running:\", p); process.exit(1); }
});"'
check "the course outline is selected" in_container bash -c 'bb settings ui get sidebar.threadListProvider --json | grep -q "\"tutor/course-outline\""'
# The agent CLIs are on BB's fixed PATH, and BB's host machine finds them.
# shellcheck disable=SC2016 # expanded in the container
check "claude, codex and pi are in /usr/local/bin" in_container bash -c 'for cli in claude codex pi; do test -x "/usr/local/bin/$cli" || { echo "missing /usr/local/bin/$cli" >&2; exit 1; }; done'
check "the agent CLIs run with BB's PATH" in_container env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -c 'claude --version && codex --version && pi --version'
check "BB sees the three providers installed" in_container bash -c 'bb updates status --json | node -e "
let s = \"\"; process.stdin.on(\"data\", (d) => (s += d)).on(\"end\", () => {
  const status = JSON.parse(s).machines[0].providerStatus;
  const missing = [\"claude-code\", \"codex\", \"pi\"].filter((id) => !(status[id] && status[id].installed));
  if (missing.length) { console.error(\"BB does not see these providers installed:\", missing, status); process.exit(1); }
});"'
check "plugins students do not need are off, and Tutor's own are on" in_container bash -c 'bb plugin list --json | node -e "
let s = \"\"; process.stdin.on(\"data\", (d) => (s += d)).on(\"end\", () => {
  const plugins = JSON.parse(s).plugins;
  const on = plugins.filter((p) => [\"automations\", \"connect\", \"scheduled-send\", \"keep-awake\"].includes(p.id) && p.enabled !== false);
  const off = plugins.filter((p) => (p.id === \"tutor\" || p.id === \"thread-list\" || p.id.startsWith(\"provider-\")) && p.enabled === false);
  if (on.length || off.length) { console.error(\"still on:\", on.map((p) => p.id), \"wrongly off:\", off.map((p) => p.id)); process.exit(1); }
});"'
check "the Tutor theme is selected" in_container bash -c 'bb theme show --json | grep -q "\"themeId\": \"plugin:tutor:paper\""'
check "config.json tells the plugin where the activity file goes" in_container node -e 'const c = require("/usr/local/etc/tutor/config.json"); if (c.dataDir !== "/home/node/.bb-state") { console.error(c); process.exit(1); }'
# Outside Codespaces the attach-time keep-alive returns at once, so it never
# holds up devcontainer up (which has already run it as postAttachCommand).
check "postAttachCommand ran tutor-keepalive" grep -q "only runs in a GitHub Codespace" "$workspace/up.log"
check "tutor-keepalive returns at once outside Codespaces" in_container bash -c 'timeout 10 tutor-keepalive | grep -q "only runs in a GitHub Codespace"'
echo 'Codespace entry point came up with Tutor running, the agent CLIs installed and BB branded'
