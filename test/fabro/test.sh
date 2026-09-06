#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "fabro on PATH" bash -c "fabro --version | grep -q '^fabro '"
check "wizard on PATH" bash -c "command -v fabro-setup"
check "status helper on PATH" bash -c "command -v fabro-status"
check "bootstrap installed" bash -c "test -x /usr/local/share/fabro/bin/fabro-bootstrap"
check "autostart installed" bash -c "test -x /usr/local/share/fabro/bin/fabro-autostart"
check "shared helpers installed" bash -c "test -r /usr/local/share/fabro/bin/fabro-common.sh"

# Autostart runs on every container start, including before setup has ever run.
# With no settings.toml it must be a silent no-op, not an error.
check "autostart no-ops before setup" bash -c "/usr/local/share/fabro/bin/fabro-autostart"

# The web origin must follow the environment: forwarded host in a Codespace,
# loopback everywhere else.
check "web url is loopback outside codespaces" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && fabro_web_url | grep -q '^http://127.0.0.1:32276$'"
check "web url follows codespaces host" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && CODESPACE_NAME=demo GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev fabro_web_url | grep -q '^https://demo-32276.app.github.dev$'"
check "options recorded for runtime" bash -c "grep -q '^FABRO_SETUP_PROVIDER=' /usr/local/share/fabro/setup.env"
check "shell banner wired into bashrc" bash -c "grep -q 'fabro/banner.sh' /etc/bash.bashrc"

# The wizard is launched from a folderOpen task, which may or may not give it a
# terminal. Without one it must explain itself and exit 0, never hang or fail.
check "wizard exits cleanly without a tty" bash -c "fabro-setup </dev/null | grep -q 'fabro-setup'"

# No provider is configured in a fresh container, so status must say so.
check "status reports unconfigured" bash -c "! fabro-status --quiet"

reportResults
