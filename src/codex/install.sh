#!/usr/bin/env bash
# Dev Container Feature installer for the OpenAI Codex CLI.
# The runtime is deliberately supplied by the consuming image or Node Feature.
set -euo pipefail

CODEX_VERSION="${VERSION:-latest}"
CODEX_MODEL="${MODEL:-}"
CODEX_FULL_ACCESS="${FULLACCESS:-false}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ "${CODEX_VERSION}" != "latest" ] \
    && ! [[ "${CODEX_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
    fail "version must be 'latest' or an exact semantic version (for example, 0.155.1); received '${CODEX_VERSION}'."
fi

# The model is interpolated into a TOML string, so restrict it to the
# characters Codex model slugs actually use.
if [ -n "${CODEX_MODEL}" ] && ! [[ "${CODEX_MODEL}" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    fail "model must be a Codex model slug such as gpt-6-sol; received '${CODEX_MODEL}'."
fi

case "${CODEX_FULL_ACCESS}" in
    true | false) ;;
    *) fail "fullAccess must be true or false; received '${CODEX_FULL_ACCESS}'." ;;
esac

if [ "$(uname -s)" != "Linux" ]; then
    fail "the Codex Feature supports Linux dev containers only."
fi

case "$(uname -m)" in
    x86_64 | aarch64) ;;
    *) fail "the official @openai/codex npm package supports Linux x64 and arm64 only; found $(uname -m)." ;;
esac

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    fail "Node.js and npm are required. Use a Node.js base image or add a Node Feature before this Feature."
fi

NODE_VERSION="$(node --version 2>/dev/null || true)"
NODE_MAJOR="${NODE_VERSION#v}"
NODE_MAJOR="${NODE_MAJOR%%.*}"
case "${NODE_MAJOR}" in
    '' | *[!0-9]*) fail "could not determine a compatible Node.js version from '${NODE_VERSION}'." ;;
esac

# @openai/codex 0.155.1 declares node >=16 in its npm package metadata.
if [ "${NODE_MAJOR}" -lt 16 ]; then
    fail "@openai/codex requires Node.js 16 or later; found ${NODE_VERSION}. Upgrade Node.js in the consuming image."
fi

echo "Installing @openai/codex@${CODEX_VERSION} with Node.js ${NODE_VERSION}"
npm install --global "@openai/codex@${CODEX_VERSION}"

# npm's global prefix can be customized by the base image. Keep the command in
# /usr/local/bin, which is on the standard path for both root and remote users.
NPM_PREFIX="$(npm prefix --global)"
CODEX_BIN="${NPM_PREFIX}/bin/codex"
if [ ! -x "${CODEX_BIN}" ]; then
    fail "npm completed but did not install an executable Codex CLI at ${CODEX_BIN}."
fi
install -d -m 0755 /usr/local/bin
if [ "${CODEX_BIN}" != "/usr/local/bin/codex" ]; then
    ln -sf "${CODEX_BIN}" /usr/local/bin/codex
fi

echo "Installed $(/usr/local/bin/codex --version)"

# Defaults go in the system config layer rather than the remote user's
# ~/.codex/config.toml, so a user's own config (or /model, /permissions) still
# wins.
defaults=()
if [ -n "${CODEX_MODEL}" ]; then
    defaults+=("model = \"${CODEX_MODEL}\"")
fi
if [ "${CODEX_FULL_ACCESS}" = true ]; then
    defaults+=(
        'sandbox_mode = "danger-full-access"'
        'approval_policy = "never"'
    )
fi

if [ "${#defaults[@]}" -gt 0 ]; then
    CODEX_SYSTEM_CONFIG=/etc/codex/config.toml
    install -d -m 0755 /etc/codex
    touch "${CODEX_SYSTEM_CONFIG}"
    # Top-level keys must precede any [table], so drop existing top-level
    # copies of the keys we set and prepend ours.
    keys=$(printf '%s\n' "${defaults[@]}" | cut -d' ' -f1 | paste -sd'|')
    {
        printf '%s\n' "${defaults[@]}"
        awk -v keys="^[[:space:]]*(${keys})[[:space:]]*=" '/^[[:space:]]*\[/ { in_table = 1 } in_table || $0 !~ keys' "${CODEX_SYSTEM_CONFIG}"
    } >"${CODEX_SYSTEM_CONFIG}.tmp"
    mv "${CODEX_SYSTEM_CONFIG}.tmp" "${CODEX_SYSTEM_CONFIG}"
    chmod 0644 "${CODEX_SYSTEM_CONFIG}"
    echo "Wrote Codex defaults to ${CODEX_SYSTEM_CONFIG}:"
    printf '  %s\n' "${defaults[@]}"
fi
