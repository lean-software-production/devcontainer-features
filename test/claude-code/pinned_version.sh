#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Claude Code is on the node user's PATH" bash -c "command -v claude"
check "pinned Claude Code runs as the node user" bash -c "claude --version | grep -Eq '^2\\.1\\.277( |$)'"

reportResults
