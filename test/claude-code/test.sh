#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "test runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Claude Code is on the node user's PATH" bash -c "command -v claude"
check "default Claude Code returns a semantic version" bash -c "claude --version | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+'"

reportResults
