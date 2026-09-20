#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Claude Code on PATH" bash -c "command -v claude"
check "Claude Code reports the pinned version" bash -c "claude --version | grep -Eq '^2\\.1\\.278( |$)'"
check "Claude Code is executable by the non-root Node image user" bash -c "runuser -u node -- claude --version | grep -Eq '^2\\.1\\.278( |$)'"

reportResults
