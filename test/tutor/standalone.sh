#!/usr/bin/env bash
# Checks run in child shells, so their $-expressions are single-quoted on purpose;
# the test library exists only inside the scenario container.
# shellcheck disable=SC2016,SC1091
set -e
source dev-container-features-test-lib

state='/tmp/tutor bb state'
export BB_SERVER_URL=http://127.0.0.1:48886 BB_HOST_DAEMON_PORT=48887 BB_DATA_DIR="$state"
fixture="$(cd "$(dirname "$0")" && pwd)/fixtures/scripted-provider"

# "<rootDir>\t<status>" of an installed plugin.
plugin_record() {
    bb plugin list --json | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const p = (JSON.parse(s).plugins || []).find((x) => x.id === process.argv[1]);
  process.stdout.write(p ? `${p.rootDir}\t${p.status}` : "");
});' "$1"
}
project_id() {
    bb project list --json | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const p = JSON.parse(s).find((x) => (x.sources || []).some((src) => src.path === process.argv[1]));
  process.stdout.write(p ? p.id : "");
});' "$1"
}
rail() { bb settings ui get sidebar.threadListProvider --json | node -e 'let s="";process.stdin.on("data",(d)=>(s+=d)).on("end",()=>process.stdout.write(JSON.parse(s).value))'; }
# "true"/"false": whether an installed plugin is enabled.
plugin_enabled() {
    bb plugin list --json | node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  const p = (JSON.parse(s).plugins || []).find((x) => x.id === process.argv[1]);
  process.stdout.write(p ? String(p.enabled !== false) : "missing");
});' "$1"
}
theme() { bb theme show --json | node -e 'let s="";process.stdin.on("data",(d)=>(s+=d)).on("end",()=>process.stdout.write(JSON.parse(s).themeId))'; }
export -f plugin_record project_id rail plugin_enabled theme
export state fixture

# Image build: a prebuilt, root-owned plugin with runtime dependencies only.
check "plugin is staged root-owned" bash -c 'test "$(stat -c %u /usr/local/share/tutor/plugin/server.ts)" = 0 && test "$(stat -c %u /usr/local/share/tutor/plugin/node_modules)" = 0 && test ! -w /usr/local/share/tutor/plugin'
check "frontend bundle was prebuilt against the packaged bb" bash -c 'grep -q "\"pluginId\": \"tutor\"" /usr/local/share/tutor/plugin/dist/app.meta.json && test -s /usr/local/share/tutor/plugin/dist/app.js'
check "only runtime dependencies are installed" bash -c 'test -d /usr/local/share/tutor/plugin/node_modules/zod && test ! -e /usr/local/share/tutor/plugin/node_modules/typescript && test ! -e /usr/local/share/tutor/plugin/node_modules/@get-bb'
check "bb build toolchain is kept for offline installs" bash -c 'ls -d /usr/local/share/tutor/toolchain/toolchain-*/node_modules/esbuild'
check "plugin config names the course and factory" bash -c 'node -e "const c=require(\"/usr/local/etc/tutor/config.json\"); process.exit(c.course===\"/home/node/course\" && c.factory===\"/home/node/my-factory\" ? 0 : 1)"'
check "plugin config names the BB state directory" bash -c 'node -e "const c=require(\"/usr/local/etc/tutor/config.json\"); process.exit(c.dataDir===process.argv[1] ? 0 : 1)" "$state"'
check "config and options are root-owned and not writable by others" bash -c 'for f in /usr/local/etc/tutor/config.json /usr/local/share/tutor/options.tsv /usr/local/share/tutor/plugin.sha256; do test "$(stat -c %u "$f")" = 0 && test $((8#$(stat -c %a "$f") & 022)) = 0 || exit 1; done'
check "lifecycle helpers are installed" bash -c 'command -v tutor-feature-bootstrap && command -v tutor-feature-autostart && command -v tutor-keepalive'
check "keep-alive returns at once outside a Codespace" bash -c 'timeout 10 tutor-keepalive | grep -q "only runs in a GitHub Codespace"'

# postCreate: the course was cloned.
check "course was cloned at post-create" bash -c 'git -C /home/node/course rev-parse --verify HEAD && test -f /home/node/course/docs/iterations/README.md'

# postStart: the plugin is path-installed from a user-owned copy of this build.
check "tutor plugin is running" bash -c 'test "$(plugin_record tutor | cut -f2)" = running'
check "plugin is installed from the digest-named copy" bash -c 'digest=$(cat /usr/local/share/tutor/plugin.sha256); test "$(plugin_record tutor | cut -f1)" = "$state/.tutor-feature/plugin-${digest:0:16}"'
check "plugin copy is user-owned and links the root-owned dependencies" bash -c 'copy=$(plugin_record tutor | cut -f1); test "$(stat -c %u "$copy/dist/app.js")" = "$(id -u)" && test "$(readlink "$copy/node_modules")" = /usr/local/share/tutor/plugin/node_modules'
check "toolchain was seeded instead of downloaded" bash -c 'ls -d "$state"/plugins/toolchain-*/node_modules/esbuild && ! grep -q "downloading the plugin build toolchain" "$state"/logs/server*.log'
check "course is a BB project" bash -c 'test -n "$(project_id /home/node/course)"'
check "missing factory is not registered" bash -c 'test -z "$(project_id /home/node/my-factory)"'
check "course rail is the sidebar thread list" bash -c 'test "$(rail)" = tutor/course-rail'
check "plugins students do not need are switched off" bash -c 'for id in automations connect scheduled-send keep-awake; do test "$(plugin_enabled "$id")" = false || exit 1; done'
check "Tutor, the thread list and the providers stay on" bash -c 'for id in tutor thread-list provider-claude-code provider-codex provider-pi; do test "$(plugin_enabled "$id")" = true || exit 1; done'
check "the Tutor theme is selected" bash -c 'test "$(theme)" = plugin:tutor:paper'

# Every start re-runs the hook: nothing is reinstalled or re-registered.
check "autostart is idempotent" bash -c 'before=$(plugin_record tutor); out=$(tutor-feature-autostart 2>&1); test "$(plugin_record tutor)" = "$before" && grep -q "already installed" <<<"$out" && grep -q "already a BB project" <<<"$out"'
check "factory is registered once it exists" bash -c 'git init -q /home/node/my-factory && tutor-feature-autostart && test -n "$(project_id /home/node/my-factory)"'
check "a student's own thread list choice is kept" bash -c 'bb settings ui set sidebar.threadListProvider thread-list/thread-list >/dev/null && tutor-feature-autostart && test "$(rail)" = thread-list/thread-list'
check "a plugin the student turns back on stays on" bash -c 'bb plugin enable automations >/dev/null && tutor-feature-autostart && test "$(plugin_enabled automations)" = true'
check "a student's own theme is kept" bash -c 'bb theme reset >/dev/null && tutor-feature-autostart && test "$(theme)" = default'

# End to end with the credential-free provider: a thread Tutor did not spawn is
# neither offered Tutor's tools nor able to run them.
check "scripted provider fixture installs" bash -c 'cp -R "$fixture" "$HOME/scripted-provider" && cd "$HOME/scripted-provider" && npm ci --omit=dev --no-audit --no-fund >/dev/null && bb plugin install "$PWD" --yes >/dev/null && test "$(plugin_record scripted-provider | cut -f2)" = running'
check "a non-Tutor thread cannot use Tutor's tools" bash -c '
    turns="$state/plugins/scripted-provider/bridge-data/turns.ndjson"
    printf "%s\n" "FORCECALL tutor_status {}" "::tutor-progress{kind=focus title=\"Start here\"}" > "$HOME/prompt.txt"
    thread=$(bb thread spawn --project "$(project_id /home/node/course)" --provider scripted --prompt-file "$HOME/prompt.txt" --json | node -e "let s=\"\";process.stdin.on(\"data\",(d)=>(s+=d)).on(\"end\",()=>process.stdout.write(JSON.parse(s).id))")
    for _ in $(seq 1 60); do grep -q "\"event\":\"turn\",\"threadId\":\"$thread\"" "$turns" 2>/dev/null && break; sleep 1; done
    node -e "
const turn = require(\"fs\").readFileSync(process.argv[1], \"utf8\").trim().split(\"\\n\").map(JSON.parse)
  .find((e) => e.event === \"turn\" && e.threadId === process.argv[2]);
const ok = turn && !turn.tools.some((t) => t.startsWith(\"tutor_\")) && !(turn.skills || []).includes(\"tutor\")
  && turn.toolReport.some((r) => r.includes(\"FORCECALL tutor_status\") && r.includes(\"ERROR\"))
  && turn.directives.some((d) => d.startsWith(\"::tutor-progress\"));
process.exit(ok ? 0 : 1);" "$turns" "$thread"'
reportResults
