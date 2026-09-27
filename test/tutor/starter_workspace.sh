#!/usr/bin/env bash
# The starter is the workspace itself (starter: ${containerWorkspaceFolder},
# as in the starter's own Codespace config): config.json names it as the repo,
# it is never cloned, and it is the BB project, named after its folder.
# Checks run in child shells, so their $-expressions are single-quoted on purpose;
# the test library exists only inside the scenario container.
# shellcheck disable=SC2016,SC1091
set -e
source dev-container-features-test-lib

# The test runs in the workspace folder, which ${containerWorkspaceFolder} names.
export BB_SERVER_URL=http://127.0.0.1:49086 BB_HOST_DAEMON_PORT=49087 BB_DATA_DIR="$HOME/.bb" workspace="$PWD"

check "the workspace variable was substituted" bash -c 'grep -qxF "STARTER	$workspace" /usr/local/share/tutor/options.tsv'
check "plugin config names the starter as the repo" bash -c 'node -e "const c=require(\"/usr/local/etc/tutor/config.json\"); process.exit(c.schemaVersion===1 && c.repo===process.env.workspace && !(\"factory\" in c) ? 0 : 1)"'
check "the starter workspace is not cloned" bash -c 'out=$(tutor-feature-bootstrap 2>&1) && grep -qF "starter found at $workspace" <<<"$out" && ! grep -q cloning <<<"$out"'
check "the starter is the BB project, named after its folder" bash -c 'bb project list --json | node -e "
let s = \"\"; process.stdin.on(\"data\", (d) => (s += d)).on(\"end\", () => {
  const w = process.env.workspace;
  const p = JSON.parse(s).find((x) => (x.sources || []).some((src) => src.type === \"local_path\" && src.path === w));
  process.exit(p && p.name === require(\"path\").basename(w) ? 0 : 1);
});"'
check "registration is idempotent" bash -c 'out=$(tutor-feature-autostart 2>&1) && grep -qF "starter $workspace is already a BB project" <<<"$out"'
reportResults
