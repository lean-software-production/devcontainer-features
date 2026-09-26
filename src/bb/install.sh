#!/usr/bin/env bash
# Dev Container Feature installer for the BB npm distribution.  This runs as
# root while the image is built; it deliberately never starts BB or creates
# user state.
set -euo pipefail

BB_VERSION="${VERSION:-0.43.3}"
BB_MODE="${MODE:-cli}"
BB_AUTOSTART="${AUTOSTART:-false}"
BB_SERVER_PORT="${SERVERPORT:-38886}"
BB_HOST_DAEMON_PORT="${HOSTDAEMONPORT:-38887}"
BB_DATA_DIR="${DATADIR:-}"
BB_APP_URL="${APPURL:-auto}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR=/usr/local/share/bb
NPM_PREFIX="${SHARE_DIR}/npm"

fail() { echo "ERROR: bb Feature: $*" >&2; exit 1; }

valid_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]; }
has_unsafe_chars() { [[ "$1" =~ [[:cntrl:]] ]] || [[ "$1" == *';'* || "$1" == *'|'* || "$1" == *'&'* || "$1" == *'$'* || "$1" == *'`'* || "$1" == *'<'* || "$1" == *'>'* ]]; }

[ "$BB_VERSION" = latest ] || valid_semver "$BB_VERSION" || fail "version must be 'latest' or an exact semantic version; received '$BB_VERSION'."
case "$BB_MODE" in cli|standalone) ;; *) fail "mode must be 'cli' or 'standalone'; received '$BB_MODE'." ;; esac
case "$BB_AUTOSTART" in true|false) ;; *) fail "autoStart must be true or false; received '$BB_AUTOSTART'." ;; esac
valid_port "$BB_SERVER_PORT" || fail "serverPort must be an integer from 1024 through 65535."
valid_port "$BB_HOST_DAEMON_PORT" || fail "hostDaemonPort must be an integer from 1024 through 65535."
[ "$BB_SERVER_PORT" != "$BB_HOST_DAEMON_PORT" ] || fail "serverPort and hostDaemonPort must be different."
[ -z "$BB_DATA_DIR" ] || { [[ "$BB_DATA_DIR" = /* ]] && ! has_unsafe_chars "$BB_DATA_DIR"; } || fail "dataDir must be an absolute path without control characters or shell metacharacters."
[ "$BB_APP_URL" = auto ] || { ! has_unsafe_chars "$BB_APP_URL"; } || fail "appUrl contains unsafe characters."

[ "$(uname -s)" = Linux ] || fail "this Feature supports Linux dev containers only."
case "$(uname -m)" in x86_64|amd64) ;; *) fail "this MVP is supported and tested on Linux amd64 only; found $(uname -m)." ;; esac
[ -r /etc/os-release ] || fail "only Debian and Ubuntu base images are supported."
. /etc/os-release
case "${ID:-}" in debian|ubuntu) ;; *) fail "only Debian and Ubuntu base images are supported; found ${ID:-unknown}." ;; esac

command -v node >/dev/null 2>&1 || fail "Node.js is required. Use a Node.js base image or add the Node Feature."
command -v npm >/dev/null 2>&1 || fail "npm is required. Use a Node.js base image or add the Node Feature."
if [ "$BB_APP_URL" != auto ]; then
    node -e 'const v=process.argv[1]; let u; try { u=new URL(v); } catch { process.exit(2); } if (!/^https?:$/.test(u.protocol)||u.origin!==v||u.username||u.password) process.exit(2);' "$BB_APP_URL" \
        || fail "appUrl must be an http(s) origin with no path, query, fragment, or credentials."
fi
NODE_VERSION="$(node --version)"
if [[ "$NODE_VERSION" =~ ^v([0-9]+)\.([0-9]+)\. ]]; then
    NODE_MAJOR="${BASH_REMATCH[1]}"; NODE_MINOR="${BASH_REMATCH[2]}"
else
    fail "could not parse Node.js version '$NODE_VERSION'."
fi
case "$NODE_MAJOR" in
    22) [ "$NODE_MINOR" -ge 19 ] || fail "bb-app requires Node.js ^22.19.0, ^24, or ^26; found $NODE_VERSION." ;;
    24|26) ;;
    *) fail "bb-app requires Node.js ^22.19.0, ^24, or ^26; found $NODE_VERSION." ;;
esac

# Native addon fallback builds need these ordinary Debian build dependencies.
missing_packages=()
command -v git >/dev/null 2>&1 || missing_packages+=(git)
command -v python3 >/dev/null 2>&1 || missing_packages+=(python3)
command -v make >/dev/null 2>&1 || missing_packages+=(make)
command -v g++ >/dev/null 2>&1 || missing_packages+=(g++)
command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
command -v setsid >/dev/null 2>&1 || missing_packages+=(util-linux)
if [ "${#missing_packages[@]}" -gt 0 ]; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates "${missing_packages[@]}"
    rm -rf /var/lib/apt/lists/*
fi

install -d -m 0755 "$SHARE_DIR" "$SHARE_DIR/bin" "$NPM_PREFIX"

# npm verifies registry integrity while packing. Verify the resulting tarball a
# second time against the registry's SHA-512 SRI before allowing addon scripts.
package_workdir="$(mktemp -d)"
trap 'rm -rf "$package_workdir"' EXIT
expected_integrity="$(npm_config_cache="$package_workdir/npm-cache" npm view "bb-app@${BB_VERSION}" dist.integrity)"
[[ "$expected_integrity" =~ ^sha512- ]] || fail "npm did not provide SHA-512 integrity metadata for bb-app@${BB_VERSION}."
package_tarball="$(cd "$package_workdir" && npm_config_cache="$package_workdir/npm-cache" npm_config_ignore_scripts=true npm pack --silent "bb-app@${BB_VERSION}")"
package_tarball="$package_workdir/$package_tarball"
[ -f "$package_tarball" ] || fail "npm pack did not produce a bb-app tarball."
actual_integrity="$(node -e 'const fs=require("fs"),crypto=require("crypto"); process.stdout.write("sha512-"+crypto.createHash("sha512").update(fs.readFileSync(process.argv[1])).digest("base64"));' "$package_tarball")"
[ "$actual_integrity" = "$expected_integrity" ] || fail "bb-app tarball integrity did not match npm registry metadata."

# Scope script permission to this one install. npm 11.16 introduced the
# allow-scripts flag and warns about unreviewed scripts; npm 12 blocks them.
# https://github.com/npm/cli/blob/v11.16.0/CHANGELOG.md
# BB 0.43.3 needs the reviewed native-addon hooks of node-pty and
# @parcel/watcher; do not use npm's
# global "allow all" escape hatch or write an npmrc policy. npm before 11.16
# does not implement --allow-scripts and retains normal script behavior.
NPM_VERSION="$(npm --version)"
if [[ "$NPM_VERSION" =~ ^([0-9]+)\.([0-9]+)\. ]]; then
    NPM_MAJOR="${BASH_REMATCH[1]}"; NPM_MINOR="${BASH_REMATCH[2]}"
else
    fail "could not parse npm version '$NPM_VERSION'."
fi
npm_install_args=(install --global --foreground-scripts)
if [ "$NPM_MAJOR" -ge 12 ] || { [ "$NPM_MAJOR" -eq 11 ] && [ "$NPM_MINOR" -ge 16 ]; }; then
    npm_install_args+=(--allow-scripts=@parcel/watcher,node-pty)
fi
npm_config_cache="$package_workdir/npm-cache" npm_config_prefix="$NPM_PREFIX" npm_config_ignore_scripts=false npm "${npm_install_args[@]}" "$package_tarball"

BB_APP_BIN="$NPM_PREFIX/bin/bb-app"
[ -x "$BB_APP_BIN" ] || fail "bb-app was installed without its launcher at $BB_APP_BIN."
INSTALLED_VERSION="$(node -e 'process.stdout.write(require(process.argv[1]+"/lib/node_modules/bb-app/package.json").version)' "$NPM_PREFIX")"
[ "$BB_VERSION" = latest ] || [ "$INSTALLED_VERSION" = "$BB_VERSION" ] || fail "installed bb-app version $INSTALLED_VERSION does not match requested $BB_VERSION."

write_option() { printf '%s\t%s\n' "$1" "$2"; }
{
    write_option VERSION "$INSTALLED_VERSION"
    write_option MODE "$BB_MODE"
    write_option AUTOSTART "$BB_AUTOSTART"
    write_option SERVER_PORT "$BB_SERVER_PORT"
    write_option HOST_DAEMON_PORT "$BB_HOST_DAEMON_PORT"
    write_option DATA_DIR "$BB_DATA_DIR"
    write_option APP_URL "$BB_APP_URL"
    write_option BB_APP_BIN "$BB_APP_BIN"
} > "$SHARE_DIR/options.tsv"
chown root:root "$SHARE_DIR/options.tsv"
chmod 0644 "$SHARE_DIR/options.tsv"

# Make BB's documented commands available without letting this Feature silently
# replace an unrelated tool supplied by the base image. Runtime helpers still
# use the private absolute launcher above, never this PATH-facing link.
link_bb_command() {
    local command="$1" source="$NPM_PREFIX/bin/$1" destination="/usr/local/bin/$1"
    [ -x "$source" ] || fail "bb-app was installed without $source."
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        [ "$(readlink -f -- "$destination")" = "$(readlink -f -- "$source")" ] || fail "refusing to replace existing $destination; remove the conflicting tool or use a base image without it."
    fi
    ln -sfn "$source" "$destination"
}
link_bb_command bb-app
link_bb_command bb
link_bb_command bb-server
link_bb_command bb-host-daemon

install -m 0755 "$FEATURE_DIR/bin/bb-feature-bootstrap" "$SHARE_DIR/bin/bb-feature-bootstrap"
install -m 0755 "$FEATURE_DIR/bin/bb-feature-autostart" "$SHARE_DIR/bin/bb-feature-autostart"
install -m 0755 "$FEATURE_DIR/bin/bb-feature-status" "$SHARE_DIR/bin/bb-feature-status"
install -m 0644 "$FEATURE_DIR/bin/bb-feature-common.sh" "$SHARE_DIR/bin/bb-feature-common.sh"
install -m 0644 "$FEATURE_DIR/NOTICE" "$SHARE_DIR/NOTICE"
ln -sfn "$SHARE_DIR/bin/bb-feature-bootstrap" /usr/local/bin/bb-feature-bootstrap
ln -sfn "$SHARE_DIR/bin/bb-feature-autostart" /usr/local/bin/bb-feature-autostart
ln -sfn "$SHARE_DIR/bin/bb-feature-status" /usr/local/bin/bb-feature-status

echo "Installed bb-app ${INSTALLED_VERSION} in ${NPM_PREFIX}; standalone mode is user-started only."
