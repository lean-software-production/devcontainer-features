#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Node.js 24 is supplied by the test image" bash -c 'test "$(node -p "process.versions.node.split(\".\")[0]")" = 24'
check "codex is on PATH" command -v codex
check "default Codex version is installed" bash -c 'codex --version | grep -qx "codex-cli 0.155.1"'

reportResults
