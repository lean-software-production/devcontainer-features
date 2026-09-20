#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "Pi is on the node user's PATH" bash -c "command -v pi"
check "default Pi runs as the node user" bash -c "pi --version | grep -q '0.86.0'"

reportResults
