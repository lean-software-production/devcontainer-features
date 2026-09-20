#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Node.js 24 is supplied by the test image" bash -c 'test "$(node -p "process.versions.node.split(\".\")[0]")" = 24'
check "test runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Codex is on the node user's PATH" command -v codex
check "default Codex returns a semantic version" bash -c 'codex --version | grep -Eq "^codex-cli [0-9]+\\.[0-9]+\\.[0-9]+"'

reportResults
