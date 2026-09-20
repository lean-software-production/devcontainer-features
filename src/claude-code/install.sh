#!/usr/bin/env bash
# Dev Container Feature installer for Claude Code. Runs as root at image build
# time; Feature option values arrive as upper-cased environment variables.
set -euo pipefail

CLAUDE_CODE_VERSION="${VERSION:-2.1.278}"
MINIMUM_NODE_MAJOR=22

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

case "${CLAUDE_CODE_VERSION}" in
    latest) package_spec='@anthropic-ai/claude-code@latest' ;;
    [0-9]*.[0-9]*.[0-9]*)
        if [[ "${CLAUDE_CODE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            package_spec="@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
        else
            fail "version must be 'latest' or an exact semantic version (for example, 2.1.278); got '${CLAUDE_CODE_VERSION}'."
        fi
        ;;
    *) fail "version must be 'latest' or an exact semantic version (for example, 2.1.278); got '${CLAUDE_CODE_VERSION}'." ;;
esac

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    fail "Claude Code requires Node.js ${MINIMUM_NODE_MAJOR}+ and npm. Use a Node.js base image or add ghcr.io/devcontainers/features/node:1 before this feature. This feature deliberately does not install Node.js."
fi

node_version="$(node --version 2>/dev/null || true)"
node_major="${node_version#v}"
node_major="${node_major%%.*}"
if ! [[ "${node_major}" =~ ^[0-9]+$ ]] || [ "${node_major}" -lt "${MINIMUM_NODE_MAJOR}" ]; then
    fail "Claude Code requires Node.js ${MINIMUM_NODE_MAJOR}+; found '${node_version:-unknown}'. Upgrade the consuming image or configure ghcr.io/devcontainers/features/node:1."
fi

echo "Installing Claude Code (${CLAUDE_CODE_VERSION}) with Node.js ${node_version}"
npm install --global --no-audit --no-fund "${package_spec}"

if ! command -v claude >/dev/null 2>&1; then
    fail "Claude Code installation completed but 'claude' is not on PATH. Check npm's global bin configuration."
fi

claude --version
echo "Claude Code installed. Run 'claude' as the remote user to authenticate."
