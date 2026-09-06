#!/usr/bin/env bash
# Dev Container Feature installer for Fabro.
# Runs as root at image build time. Option values arrive as uppercased env vars.
set -euo pipefail

FABRO_VERSION="${VERSION:-0.254.0}"
FABRO_PROVIDER="${PROVIDER:-openai}"
FABRO_AUTOSTART="${AUTOSTARTSERVER:-true}"
FABRO_BANNER="${SHELLBANNER:-true}"

REMOTE_USER="${_REMOTE_USER:-root}"
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-/root}"

SHARE_DIR=/usr/local/share/fabro
FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Fabro (version=${FABRO_VERSION}, provider=${FABRO_PROVIDER}) for user ${REMOTE_USER}"

# --- dependencies -----------------------------------------------------------
# curl and ca-certificates are needed both to fetch the release and, later, for
# the device-code login to reach auth.openai.com.
if ! command -v curl >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y --no-install-recommends curl ca-certificates
    rm -rf /var/lib/apt/lists/*
fi

# --- resolve version --------------------------------------------------------
if [ "${FABRO_VERSION}" = "latest" ]; then
    FABRO_VERSION="$(curl -fsSL https://api.github.com/repos/fabro-sh/fabro/releases/latest \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
        | head -n 1)"
    if [ -z "${FABRO_VERSION}" ]; then
        echo "Could not resolve the latest Fabro release from the GitHub API." >&2
        exit 1
    fi
    echo "Resolved 'latest' to ${FABRO_VERSION}"
fi

# --- download and verify the binary ----------------------------------------
arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "${arch}" in
    amd64 | x86_64) target="x86_64-unknown-linux-musl" ;;
    arm64 | aarch64) target="aarch64-unknown-linux-musl" ;;
    *)
        echo "Unsupported architecture: ${arch}" >&2
        exit 1
        ;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
cd "${workdir}"

archive="fabro-${target}.tar.gz"
url="https://github.com/fabro-sh/fabro/releases/download/v${FABRO_VERSION}"
curl -fsSLO "${url}/${archive}"
curl -fsSLO "${url}/${archive}.sha256"
sha256sum --check "${archive}.sha256"
tar -xzf "${archive}"
install -m 0755 "fabro-${target}/fabro" /usr/local/bin/fabro
cd /
fabro --version

# --- install the setup scripts ---------------------------------------------
install -d -m 0755 "${SHARE_DIR}/bin"
install -m 0755 "${FEATURE_DIR}/bin/fabro-bootstrap" "${SHARE_DIR}/bin/fabro-bootstrap"
install -m 0755 "${FEATURE_DIR}/bin/fabro-setup" "${SHARE_DIR}/bin/fabro-setup"
install -m 0755 "${FEATURE_DIR}/bin/fabro-status" "${SHARE_DIR}/bin/fabro-status"
ln -sf "${SHARE_DIR}/bin/fabro-setup" /usr/local/bin/fabro-setup
ln -sf "${SHARE_DIR}/bin/fabro-status" /usr/local/bin/fabro-status

# Runtime scripts read the resolved option values from here, because Feature
# options are only present as env vars during this build step.
cat > "${SHARE_DIR}/setup.env" <<EOF
FABRO_SETUP_PROVIDER=${FABRO_PROVIDER}
FABRO_SETUP_AUTOSTART=${FABRO_AUTOSTART}
FABRO_SETUP_BANNER=${FABRO_BANNER}
FABRO_SETUP_MARKER=${REMOTE_USER_HOME}/.fabro/.setup-complete
EOF
chmod 0644 "${SHARE_DIR}/setup.env"

# --- shell banner -----------------------------------------------------------
if [ "${FABRO_BANNER}" = "true" ]; then
    cat > "${SHARE_DIR}/banner.sh" <<'EOF'
# Sourced by interactive shells. Prints a setup hint until setup is complete.
# Deliberately cheap: a file test, never a network or server call.
if [ -n "${PS1-}" ] && [ -z "${FABRO_BANNER_SHOWN-}" ]; then
    export FABRO_BANNER_SHOWN=1
    if [ -r /usr/local/share/fabro/setup.env ]; then
        . /usr/local/share/fabro/setup.env
        if [ ! -f "${FABRO_SETUP_MARKER:-$HOME/.fabro/.setup-complete}" ]; then
            printf '\n  \033[1;36mFabro is not configured yet.\033[0m Run \033[1mfabro-setup\033[0m to connect your LLM account.\n\n'
        fi
    fi
fi
EOF
    chmod 0644 "${SHARE_DIR}/banner.sh"

    snippet='[ -r /usr/local/share/fabro/banner.sh ] && . /usr/local/share/fabro/banner.sh'
    for rc in /etc/bash.bashrc /etc/zsh/zshrc; do
        if [ -f "${rc}" ] && ! grep -qF 'fabro/banner.sh' "${rc}"; then
            printf '\n%s\n' "${snippet}" >> "${rc}"
        fi
    done
fi

echo "Fabro feature installed. The wizard is available as 'fabro-setup'."
