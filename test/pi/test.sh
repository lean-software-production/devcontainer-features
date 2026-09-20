#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Node 24 is supplied by the test image" bash -c "node --version | grep -q '^v24\\.'"
check "test runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Pi is on the node user's PATH" bash -c "command -v pi"
check "default Pi returns a semantic version" bash -c "pi --version | grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+'"
check "Pi package is globally installed" bash -c "npm list --global --depth=0 @earendil-works/pi-coding-agent | grep -Eq '@earendil-works/pi-coding-agent@[0-9]+\\.[0-9]+\\.[0-9]+'"

reportResults
