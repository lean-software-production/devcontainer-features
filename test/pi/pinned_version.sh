#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Pi is on the node user's PATH" bash -c "command -v pi"
check "pinned Pi runs as the node user" bash -c "pi --version | grep -q '0.85.0'"
check "pinned Pi package is globally installed" bash -c "npm list --global --depth=0 @earendil-works/pi-coding-agent | grep -q '@earendil-works/pi-coding-agent@0.85.0'"

reportResults
