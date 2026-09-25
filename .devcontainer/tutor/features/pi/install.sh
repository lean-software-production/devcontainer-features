#!/usr/bin/env bash
# Dev Container Feature installer for Pi Coding Agent.
# Runs as root at image build time. Option values arrive as uppercased env vars.
set -euo pipefail

PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_VERSION="${VERSION:-latest}"
MIN_NODE_VERSION="22.19.0"

version_is_at_least() {
    local actual="$1" required="$2"
    local actual_major actual_minor actual_patch required_major required_minor required_patch

    actual="${actual#v}"
    required="${required#v}"
    IFS=. read -r actual_major actual_minor actual_patch <<<"${actual}"
    IFS=. read -r required_major required_minor required_patch <<<"${required}"

    [[ "${actual_major}" =~ ^[0-9]+$ ]] || return 1
    [[ "${actual_minor}" =~ ^[0-9]+$ ]] || return 1
    [[ "${actual_patch}" =~ ^[0-9]+$ ]] || return 1

    if (( actual_major != required_major )); then
        (( actual_major > required_major ))
    elif (( actual_minor != required_minor )); then
        (( actual_minor > required_minor ))
    else
        (( actual_patch >= required_patch ))
    fi
}

if ! command -v node >/dev/null 2>&1; then
    echo "Pi requires Node.js ${MIN_NODE_VERSION} or newer, but 'node' was not found." >&2
    echo "Install Node.js in the consuming image or add a Node Feature before this Pi Feature." >&2
    exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "Pi requires npm, but 'npm' was not found." >&2
    echo "Install npm with the Node.js runtime owned by the consuming image or Feature." >&2
    exit 1
fi

NODE_VERSION="$(node --version)"
if ! version_is_at_least "${NODE_VERSION}" "${MIN_NODE_VERSION}"; then
    echo "Pi requires Node.js ${MIN_NODE_VERSION} or newer; found ${NODE_VERSION}." >&2
    echo "Upgrade Node.js in the consuming image or Feature, then rebuild the container." >&2
    exit 1
fi

if [[ "${PI_VERSION}" != "latest" ]] && ! [[ "${PI_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid Pi version '${PI_VERSION}'. Use 'latest' or an exact npm version such as '0.86.0'." >&2
    exit 1
fi

echo "Installing Pi (${PI_PACKAGE}@${PI_VERSION}) with Node ${NODE_VERSION}"

# This is Pi's documented npm command. Pi does not require lifecycle scripts
# for normal npm installs, so disable them during this root build step.
npm install --global --ignore-scripts "${PI_PACKAGE}@${PI_VERSION}"

NPM_GLOBAL_PREFIX="$(npm prefix --global)"
PI_BIN="${NPM_GLOBAL_PREFIX}/bin/pi"
if [ ! -x "${PI_BIN}" ]; then
    echo "Pi was installed but its executable was not found at ${PI_BIN}." >&2
    exit 1
fi

# Global npm prefixes vary by base image. Ensure a conventional system path
# exposes Pi to the non-root remote user as well as to root.
if [ "${PI_BIN}" != "/usr/local/bin/pi" ]; then
    install -d -m 0755 /usr/local/bin
    ln -sf "${PI_BIN}" /usr/local/bin/pi
fi

pi --version
echo "Pi installed. Start an interactive session with 'pi', then run '/login'."
