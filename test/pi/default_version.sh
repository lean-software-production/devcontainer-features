#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Pi is on the node user's PATH" bash -c "command -v pi"
check "default Pi returns a semantic version" bash -c "pi --version | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+'"

reportResults
