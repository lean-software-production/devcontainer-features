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

# The canonical origin must match the Host browsers actually send, which is
# localhost in a Codespace (the forwarder proxies in as localhost) and on a
# published dev container port alike. Pointing it at the forwarded name sends
# the browser into a redirect loop, so this must not vary by environment.
check "web url is localhost outside codespaces" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && unset CODESPACE_NAME GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN && fabro_web_url | grep -q '^http://localhost:32276$'"
check "web url stays localhost inside a codespace" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && CODESPACE_NAME=demo GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev fabro_web_url | grep -q '^http://localhost:32276$'"

# The address shown to a human is the forwarded name, and is display-only.
check "browse url is localhost outside codespaces" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && unset CODESPACE_NAME GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN && fabro_browse_url | grep -q '^http://localhost:32276$'"
check "browse url uses the forwarded host in a codespace" bash -c \
  "source /usr/local/share/fabro/bin/fabro-common.sh && CODESPACE_NAME=demo GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN=app.github.dev fabro_browse_url | grep -q '^https://demo-32276.app.github.dev$'"
check "options recorded for runtime" bash -c "grep -q '^FABRO_SETUP_PROVIDER=' /usr/local/share/fabro/setup.env"
check "model option defaults to auto" bash -c "grep -q '^FABRO_SETUP_MODEL=auto$' /usr/local/share/fabro/setup.env"
check "shell banner wired into bashrc" bash -c "grep -q 'fabro/banner.sh' /etc/bash.bashrc"

# The wizard is launched from a folderOpen task, which may or may not give it a
# terminal. Without one it must explain itself and exit 0, never hang or fail.
check "wizard exits cleanly without a tty" bash -c "fabro-setup </dev/null | grep -q 'fabro-setup'"

# No provider is configured in a fresh container, so status must say so.
check "status reports unconfigured" bash -c "! fabro-status --quiet"

reportResults
