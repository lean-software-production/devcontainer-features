#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Node.js 24 is supplied by the test image" bash -c 'test "$(node -p "process.versions.node.split(\".\")[0]")" = 24'
check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Codex is on the node user's PATH" bash -c "command -v codex"
check "pinned Codex runs as the node user" bash -c 'codex --version | grep -qx "codex-cli 0.154.0"'

reportResults
