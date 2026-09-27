#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Dev Container Feature installer for Tutor. This runs as root while the image
# is built, after the bb Feature. It downloads a checksummed release of the
# plugin (lean-software-production/bb-plugin-tutor; by default the pinned one,
# or the newest with pluginVersion "latest") and prebuilds it so
# that nothing is fetched when the container starts; it never starts BB or
# creates user state.
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The default plugin release and its SHA-256 live in plugin-pin.sh.
# shellcheck source=plugin-pin.sh
. "$FEATURE_DIR/plugin-pin.sh"
# shellcheck source=bin/tutor-plugin-fetch.sh
. "$FEATURE_DIR/bin/tutor-plugin-fetch.sh"

TUTOR_COURSE="${COURSE-/workspaces/tutorial}"
TUTOR_COURSE_REPO="${COURSEREPO-https://github.com/lean-software-production/tutorial.git}"
TUTOR_STARTER="${STARTER-}"
TUTOR_STARTER_REPO="${STARTERREPO-}"
TUTOR_FACTORY="${FACTORY-}"
TUTOR_SELECT_OUTLINE="${SELECTOUTLINE:-true}"
TUTOR_DISABLE_PLUGINS="${DISABLEPLUGINS-automations,workflows,tasks,scheduled-send,github,browser-automation,agent-annotations,connect,plugin-api-docs,plugin-api-tester,theme-preview,keep-awake,account-pool,environment-modal-sandbox}"
TUTOR_THEME="${THEME-plugin:tutor:paper}"
TUTOR_PLUGIN_VERSION="${PLUGINVERSION-$TUTOR_PLUGIN_PINNED_VERSION}"
TUTOR_PLUGIN_SHA256="${PLUGINSHA256-}"

SHARE_DIR=/usr/local/share/tutor
PLUGIN_DIR="$SHARE_DIR/plugin"
TOOLCHAIN_DIR="$SHARE_DIR/toolchain"
CONFIG_DIR=/usr/local/etc/tutor
BB_SHARE=/usr/local/share/bb

fail() { echo "ERROR: tutor Feature: $*" >&2; exit 1; }

has_unsafe_chars() { [[ "$1" =~ [[:cntrl:]] ]] || [[ "$1" == *';'* || "$1" == *'|'* || "$1" == *'&'* || "$1" == *'$'* || "$1" == *'`'* || "$1" == *'<'* || "$1" == *'>'* || "$1" == *\"* || "$1" == *\\* ]]; }
# Absolute, no shell metacharacters, no dot segments, not the root itself.
valid_path() {
    [[ "$1" = /?* ]] && ! has_unsafe_chars "$1" || return 1
    [[ "/$1/" != *'/./'* && "/$1/" != *'/../'* ]]
}
strip_trailing_slashes() { local value="$1"; while [ "${#value}" -gt 1 ] && [[ "$value" = */ ]]; do value="${value%/}"; done; printf '%s' "$value"; }

TUTOR_COURSE="$(strip_trailing_slashes "$TUTOR_COURSE")"
TUTOR_FACTORY="$(strip_trailing_slashes "$TUTOR_FACTORY")"
TUTOR_STARTER="$(strip_trailing_slashes "$TUTOR_STARTER")"
# Codespaces and the devcontainer CLI substitute ${containerWorkspaceFolder} in
# Feature options; a tool that does not would leave the text as it is.
# shellcheck disable=SC2016 # the literal text is the message
[[ "$TUTOR_STARTER" != *'${'* ]] || fail "starter is '$TUTOR_STARTER', which holds an unsubstituted \${...} variable: whatever built this container did not substitute it. Set starter to an absolute path, or build with the devcontainer CLI or Codespaces, which substitute \${containerWorkspaceFolder}."
valid_path "$TUTOR_COURSE" || fail "course must be an absolute path without dot segments, control characters, quotes or shell metacharacters; received '$TUTOR_COURSE'."
[ -z "$TUTOR_STARTER" ] || valid_path "$TUTOR_STARTER" || fail "starter must be empty or an absolute path without dot segments, control characters, quotes or shell metacharacters; received '$TUTOR_STARTER'."
[ -z "$TUTOR_STARTER" ] || [ "$TUTOR_STARTER" != "$TUTOR_COURSE" ] || fail "starter and course must be different directories."
[ -z "$TUTOR_FACTORY" ] || valid_path "$TUTOR_FACTORY" || fail "factory must be empty or an absolute path without dot segments, control characters, quotes or shell metacharacters; received '$TUTOR_FACTORY'."
[ -z "$TUTOR_FACTORY" ] || [ "$TUTOR_FACTORY" != "$TUTOR_COURSE" ] || fail "factory and course must be different directories."
case "$TUTOR_SELECT_OUTLINE" in true|false) ;; *) fail "selectOutline must be true or false; received '$TUTOR_SELECT_OUTLINE'." ;; esac
# The same rules as the start-up hook's tutor_plugin_list and tutor_theme_id.
if [ -n "$TUTOR_DISABLE_PLUGINS" ]; then
    [[ "$TUTOR_DISABLE_PLUGINS" =~ ^[a-z0-9][a-z0-9-]*(,[a-z0-9][a-z0-9-]*)*$ ]] \
        || fail "disablePlugins must be empty or comma-separated plugin ids (lower-case letters, digits and '-', no spaces); received '$TUTOR_DISABLE_PLUGINS'."
fi
for tutor_plugin in ${TUTOR_DISABLE_PLUGINS//,/ }; do
    case "$tutor_plugin" in
        tutor|thread-list|provider-*|environment-project-checkout|environment-personal-workspace|environment-git-worktree)
            echo "tutor Feature: disablePlugins lists '$tutor_plugin', which Tutor needs; it will never be disabled." >&2 ;;
    esac
done
if [ -n "$TUTOR_THEME" ]; then
    [[ "$TUTOR_THEME" =~ ^[A-Za-z0-9][A-Za-z0-9:._-]*$ ]] \
        || fail "theme must be empty or a BB theme id such as 'plugin:tutor:paper' or 'nord'; received '$TUTOR_THEME'."
fi
# courseRepo and starterRepo: <option name> <value>.
check_repo_text() {
    [ -z "$2" ] || { [[ "$2" = https://* ]] && ! has_unsafe_chars "$2" && [[ "$2" != *[[:space:]]* ]]; } \
        || fail "$1 must be empty or an https:// URL without spaces or shell metacharacters."
}
check_repo_text courseRepo "$TUTOR_COURSE_REPO"
check_repo_text starterRepo "$TUTOR_STARTER_REPO"
[ -z "$TUTOR_STARTER_REPO" ] || [ -n "$TUTOR_STARTER" ] || fail "starterRepo needs a starter to clone into; set starter too, or leave starterRepo empty."
# pluginVersion and pluginSha256. The pinned version uses the pinned SHA-256;
# a pluginSha256 given with it must equal the pin. Any other explicit version
# needs its own pluginSha256, because for those the release's .sha256 file is
# never trusted. "latest" is resolved when the plugin is fetched below and is
# checked only against that release's own .sha256 (corruption, not a
# compromised release), so no pluginSha256 can apply to it.
[ "$TUTOR_PLUGIN_VERSION" = latest ] || tutor_plugin_valid_version "$TUTOR_PLUGIN_VERSION" \
    || fail "pluginVersion must be 'latest' or a plain semantic version such as 0.1.0 (no 'v' prefix, range or build metadata); received '$TUTOR_PLUGIN_VERSION'."
[ -z "$TUTOR_PLUGIN_SHA256" ] || [ "$TUTOR_PLUGIN_VERSION" = latest ] || tutor_plugin_valid_sha256 "$TUTOR_PLUGIN_SHA256" \
    || fail "pluginSha256 must be empty or 64 lower-case hex digits: the SHA-256 of bb-plugin-tutor-<pluginVersion>.tgz."
if [ "$TUTOR_PLUGIN_VERSION" = latest ]; then
    [ -z "$TUTOR_PLUGIN_SHA256" ] \
        || fail "pluginSha256 must be empty when pluginVersion is 'latest': the version is only known when the image is built, so no checksum can be given for it. Set pluginVersion to an explicit version to pin a checksum."
    tutor_plugin_sha256=
elif [ "$TUTOR_PLUGIN_VERSION" = "$TUTOR_PLUGIN_PINNED_VERSION" ]; then
    [ -z "$TUTOR_PLUGIN_SHA256" ] || [ "$TUTOR_PLUGIN_SHA256" = "$TUTOR_PLUGIN_PINNED_SHA256" ] \
        || fail "pluginSha256 differs from this Feature's pinned SHA-256 for plugin $TUTOR_PLUGIN_VERSION; leave pluginSha256 empty to use the pin."
    tutor_plugin_sha256="$TUTOR_PLUGIN_PINNED_SHA256"
else
    [ -n "$TUTOR_PLUGIN_SHA256" ] \
        || fail "pluginSha256 is required when pluginVersion ($TUTOR_PLUGIN_VERSION) is not this Feature's pinned $TUTOR_PLUGIN_PINNED_VERSION; set it to the SHA-256 of bb-plugin-tutor-$TUTOR_PLUGIN_VERSION.tgz."
    tutor_plugin_sha256="$TUTOR_PLUGIN_SHA256"
fi

command -v node >/dev/null 2>&1 || fail "Node.js is required; use a Node.js base image, as the bb Feature does."
command -v npm >/dev/null 2>&1 || fail "npm is required; use a Node.js base image, as the bb Feature does."
check_repo_url() {
    [ -z "$2" ] || node -e 'let u; try { u = new URL(process.argv[1]); } catch { process.exit(2); } if (u.protocol !== "https:" || u.username || u.password || u.search || u.hash) process.exit(2);' "$2" \
        || fail "$1 must be an https:// URL with no credentials, query or fragment."
}
check_repo_url courseRepo "$TUTOR_COURSE_REPO"
check_repo_url starterRepo "$TUTOR_STARTER_REPO"

# The plugin runs inside the bb Feature's standalone server and is built with
# its packaged CLI, so that Feature must already be installed.
[ -f "$BB_SHARE/bin/bb-feature-common.sh" ] || fail "the bb Feature must be installed first. Add it to the configuration, and when both are local Features list them in overrideFeatureInstallOrder (bb before tutor)."
# shellcheck source=../bb/bin/bb-feature-common.sh
. "$BB_SHARE/bin/bb-feature-common.sh"
bb_feature_validate_options || fail "the bb Feature's saved options are invalid."
[ "$BB_FEATURE_MODE" = standalone ] || fail "the bb Feature must use mode 'standalone'; Tutor runs inside the local BB server."
[ "$BB_FEATURE_AUTOSTART" = true ] || echo "tutor Feature: bb autoStart is off; after starting BB yourself, run tutor-feature-autostart to install the plugin." >&2
BB_CLI="$(dirname "$BB_FEATURE_APP_BIN")/bb"
[ -x "$BB_CLI" ] || fail "the bb Feature's packaged CLI is missing at $BB_CLI."

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Stage the plugin sources from the chosen release. The tarball is verified
# against the SHA-256 before it is read, and every member is checked before it
# is extracted; it carries no node_modules or dist, which are built below.
[ "$TUTOR_PLUGIN_VERSION" = latest ] || tutor_plugin_valid_sha256 "$tutor_plugin_sha256" \
    || fail "this Feature's pinned SHA-256 for plugin $TUTOR_PLUGIN_PINNED_VERSION is not set yet (plugin-pin.sh holds a placeholder). Set pluginVersion and pluginSha256 to a released plugin."
rm -rf "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
install -d -m 0755 "$SHARE_DIR" "$SHARE_DIR/bin" "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
if [ "$TUTOR_PLUGIN_VERSION" = latest ]; then
    tutor_plugin_fetch_latest "$workdir" "$PLUGIN_DIR" \
        || fail "could not install the latest bb-plugin-tutor release${TUTOR_PLUGIN_LATEST_VERSION:+ ($TUTOR_PLUGIN_LATEST_VERSION)}; see the message above."
    tutor_plugin_sha256="$TUTOR_PLUGIN_LATEST_SHA256"
    tutor_plugin_checked="the latest release, checked against its own .sha256 only"
else
    tutor_plugin_fetch "$TUTOR_PLUGIN_VERSION" "$tutor_plugin_sha256" "$workdir" "$PLUGIN_DIR" \
        || fail "could not install bb-plugin-tutor $TUTOR_PLUGIN_VERSION; see the message above."
    tutor_plugin_checked="checked against the pinned or given SHA-256"
fi

# Runtime dependencies only: bb shims the SDK and UI packages for plugins, and
# none of the runtime dependencies needs an install script.
(cd "$PLUGIN_DIR" && npm_config_cache="$workdir/npm-cache" npm ci --omit=dev --ignore-scripts --no-audit --no-fund)

# bb downloads its plugin build toolchain into <dataDir>/plugins on first use.
# Build against a throwaway state directory, then keep that toolchain so the
# start-up hook can seed the learner's state instead of downloading it.
build_state="$workdir/bb-state"
install -d -m 0700 "$build_state"
env -i HOME="$workdir" PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    BB_DATA_DIR="$build_state" npm_config_cache="$workdir/npm-cache" \
    "$BB_CLI" plugin build "$PLUGIN_DIR"
for artifact in app.js app.css app.meta.json; do
    [ -s "$PLUGIN_DIR/dist/$artifact" ] || fail "bb plugin build did not produce dist/$artifact."
done
toolchains=("$build_state"/plugins/toolchain-*)
[ -d "${toolchains[0]}" ] || fail "bb plugin build did not leave a build toolchain to seed."
mv "${toolchains[@]}" "$TOOLCHAIN_DIR/"

chown -R root:root "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
chmod -R u+rwX,go+rX,go-w "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
# Plugin sources are data, whatever modes the release archive recorded.
find "$PLUGIN_DIR" -path "$PLUGIN_DIR/node_modules" -prune -o -type f -exec chmod 0644 {} +
# The start-up hook stages a user-owned copy per plugin build (a path install
# rewrites dist/), keyed by this digest. dist/ is included so that a new bb-app
# producing a different bundle from the same sources still gets a fresh copy.
(cd "$PLUGIN_DIR" && find . -path ./node_modules -prune -o -type f -print0 \
    | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1) > "$SHARE_DIR/plugin.sha256"

# The BB state directory the hooks use, resolved as bb_feature_data_dir does
# for the remote user, so the plugin can find <dataDir>/.tutor-feature.
if [ -n "$BB_FEATURE_RAW_DATA_DIR" ]; then
    tutor_data_dir="$BB_FEATURE_RAW_DATA_DIR"
elif [ -n "${_REMOTE_USER_HOME:-}" ] && valid_path "${_REMOTE_USER_HOME%/}"; then
    tutor_data_dir="${_REMOTE_USER_HOME%/}/.bb"
else
    tutor_data_dir=
    echo "tutor Feature: the remote user's home is unknown, so config.json has no dataDir." >&2
fi

# The plugin reads course/repo/factory/dataDir from this JSON; the hooks read
# options.tsv. schemaVersion 1 is the contract with bb-plugin-tutor, which
# treats a missing value as 1, refuses any other and ignores unknown keys, so
# the optional repo (the starter: the student's repo) needs no new version.
install -d -m 0755 "$CONFIG_DIR"
node -e '
const [course, repo, factory, dataDir] = process.argv.slice(1);
const config = { schemaVersion: 1, course };
if (repo) config.repo = repo;
if (factory) config.factory = factory;
if (dataDir) config.dataDir = dataDir;
process.stdout.write(JSON.stringify(config, null, 2) + "\n");
' "$TUTOR_COURSE" "$TUTOR_STARTER" "$TUTOR_FACTORY" "$tutor_data_dir" > "$CONFIG_DIR/config.json"
write_option() { printf '%s\t%s\n' "$1" "$2"; }
{
    write_option COURSE "$TUTOR_COURSE"
    write_option COURSE_REPO "$TUTOR_COURSE_REPO"
    write_option STARTER "$TUTOR_STARTER"
    write_option STARTER_REPO "$TUTOR_STARTER_REPO"
    write_option FACTORY "$TUTOR_FACTORY"
    write_option SELECT_OUTLINE "$TUTOR_SELECT_OUTLINE"
    write_option DISABLE_PLUGINS "$TUTOR_DISABLE_PLUGINS"
    write_option THEME "$TUTOR_THEME"
} > "$SHARE_DIR/options.tsv"
chown root:root "$CONFIG_DIR/config.json" "$SHARE_DIR/options.tsv" "$SHARE_DIR/plugin.sha256"
chmod 0644 "$CONFIG_DIR/config.json" "$SHARE_DIR/options.tsv" "$SHARE_DIR/plugin.sha256"

install -m 0755 "$FEATURE_DIR/bin/tutor-feature-bootstrap" "$SHARE_DIR/bin/tutor-feature-bootstrap"
install -m 0755 "$FEATURE_DIR/bin/tutor-feature-autostart" "$SHARE_DIR/bin/tutor-feature-autostart"
install -m 0755 "$FEATURE_DIR/bin/tutor-keepalive" "$SHARE_DIR/bin/tutor-keepalive"
install -m 0644 "$FEATURE_DIR/bin/tutor-feature-common.sh" "$SHARE_DIR/bin/tutor-feature-common.sh"
ln -sfn "$SHARE_DIR/bin/tutor-feature-bootstrap" /usr/local/bin/tutor-feature-bootstrap
ln -sfn "$SHARE_DIR/bin/tutor-feature-autostart" /usr/local/bin/tutor-feature-autostart
ln -sfn "$SHARE_DIR/bin/tutor-keepalive" /usr/local/bin/tutor-keepalive

plugin_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$PLUGIN_DIR/package.json")"
echo "Installed the Tutor plugin ${plugin_version} (sha256 ${tutor_plugin_sha256}, ${tutor_plugin_checked}) in ${PLUGIN_DIR}; it is path-installed into BB when the container starts."
