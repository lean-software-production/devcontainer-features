#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "system config sets the default model" grep -qx 'model = "gpt-6-sol"' /etc/codex/config.toml
check "system config is readable by the remote user" test -r /etc/codex/config.toml
check "Codex reports the configured default model" bash -c 'codex doctor 2>&1 | grep -Eq "^[[:space:]]+model[[:space:]]+gpt-6-sol"'

reportResults
