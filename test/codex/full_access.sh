#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "scenario runs as the node remote user" bash -c 'test "$(id -un)" = node'
check "system config keeps the default model" grep -qx 'model = "gpt-6-sol"' /etc/codex/config.toml
check "system config disables the sandbox" grep -qx 'sandbox_mode = "danger-full-access"' /etc/codex/config.toml
check "system config never asks for approval" grep -qx 'approval_policy = "never"' /etc/codex/config.toml
check "Codex reports full access" bash -c 'codex doctor 2>&1 | grep -q "unrestricted fs + enabled network · approval Never"'

reportResults
