#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "fabro on PATH" bash -c "fabro --version | grep -q '^fabro '"
check "wizard on PATH" bash -c "command -v fabro-setup"
check "status helper on PATH" bash -c "command -v fabro-status"
check "bootstrap installed" bash -c "test -x /usr/local/share/fabro/bin/fabro-bootstrap"
check "options recorded for runtime" bash -c "grep -q '^FABRO_SETUP_PROVIDER=' /usr/local/share/fabro/setup.env"
check "shell banner wired into bashrc" bash -c "grep -q 'fabro/banner.sh' /etc/bash.bashrc"

# The wizard is launched from a folderOpen task, which may or may not give it a
# terminal. Without one it must explain itself and exit 0, never hang or fail.
check "wizard exits cleanly without a tty" bash -c "fabro-setup </dev/null | grep -q 'fabro-setup'"

# No provider is configured in a fresh container, so status must say so.
check "status reports unconfigured" bash -c "! fabro-status --quiet"

reportResults
