#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "pinned Claude Code version installed" bash -c "claude --version | grep -Eq '^2\\.1\\.278( |$)'"
check "Claude Code executable is globally available" bash -c "test -x \"$(command -v claude)\""

reportResults
