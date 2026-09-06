#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "pinned version installed" bash -c "fabro --version | grep -q '0.254.0'"
check "provider option recorded" bash -c "grep -q '^FABRO_SETUP_PROVIDER=anthropic$' /usr/local/share/fabro/setup.env"
check "model option recorded" bash -c "grep -q '^FABRO_SETUP_MODEL=none$' /usr/local/share/fabro/setup.env"
check "autostart disabled" bash -c "grep -q '^FABRO_SETUP_AUTOSTART=false$' /usr/local/share/fabro/setup.env"
check "banner not installed" bash -c "! grep -q 'fabro/banner.sh' /etc/bash.bashrc"

reportResults
