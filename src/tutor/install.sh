#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Dev Container Feature installer for Tutor. This runs as root while the image
# is built, after the bb Feature. It stages and prebuilds the plugin so that
# nothing is fetched when the container starts; it never starts BB or creates
# user state.
set -euo pipefail

TUTOR_COURSE="${COURSE-/workspaces/tutorial}"
TUTOR_COURSE_REPO="${COURSEREPO-https://github.com/lean-software-production/tutorial.git}"
TUTOR_FACTORY="${FACTORY-}"
TUTOR_SELECT_RAIL="${SELECTRAIL:-true}"
TUTOR_DISABLE_PLUGINS="${DISABLEPLUGINS-automations,workflows,tasks,scheduled-send,github,browser-automation,agent-annotations,connect,plugin-api-docs,plugin-api-tester,theme-preview,keep-awake,account-pool,environment-modal-sandbox}"
TUTOR_THEME="${THEME-plugin:tutor:paper}"

FEATURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
valid_path "$TUTOR_COURSE" || fail "course must be an absolute path without dot segments, control characters, quotes or shell metacharacters; received '$TUTOR_COURSE'."
[ -z "$TUTOR_FACTORY" ] || valid_path "$TUTOR_FACTORY" || fail "factory must be empty or an absolute path without dot segments, control characters, quotes or shell metacharacters; received '$TUTOR_FACTORY'."
[ -z "$TUTOR_FACTORY" ] || [ "$TUTOR_FACTORY" != "$TUTOR_COURSE" ] || fail "factory and course must be different directories."
case "$TUTOR_SELECT_RAIL" in true|false) ;; *) fail "selectRail must be true or false; received '$TUTOR_SELECT_RAIL'." ;; esac
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
if [ -n "$TUTOR_COURSE_REPO" ]; then
    { [[ "$TUTOR_COURSE_REPO" = https://* ]] && ! has_unsafe_chars "$TUTOR_COURSE_REPO" && [[ "$TUTOR_COURSE_REPO" != *[[:space:]]* ]]; } \
        || fail "courseRepo must be empty or an https:// URL without spaces or shell metacharacters."
fi

command -v node >/dev/null 2>&1 || fail "Node.js is required; use a Node.js base image, as the bb Feature does."
command -v npm >/dev/null 2>&1 || fail "npm is required; use a Node.js base image, as the bb Feature does."
if [ -n "$TUTOR_COURSE_REPO" ]; then
    node -e 'let u; try { u = new URL(process.argv[1]); } catch { process.exit(2); } if (u.protocol !== "https:" || u.username || u.password || u.search || u.hash) process.exit(2);' "$TUTOR_COURSE_REPO" \
        || fail "courseRepo must be an https:// URL with no credentials, query or fragment."
fi

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

# Stage the plugin source. A developer checkout may carry node_modules and
# dist; both are rebuilt here from the lockfile so the image is reproducible.
rm -rf "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
install -d -m 0755 "$SHARE_DIR" "$SHARE_DIR/bin" "$PLUGIN_DIR" "$TOOLCHAIN_DIR"
[ -f "$FEATURE_DIR/plugin/package.json" ] && [ -f "$FEATURE_DIR/plugin/package-lock.json" ] || fail "the plugin source is missing from the Feature."
tar -C "$FEATURE_DIR/plugin" --exclude=./node_modules --exclude=./dist -cf - . | tar -C "$PLUGIN_DIR" --no-same-owner -xf -

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
# The Feature content arrives with every file executable; plugin sources are data.
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

# The plugin reads course/factory/dataDir from this JSON; the hooks read options.tsv.
install -d -m 0755 "$CONFIG_DIR"
node -e '
const [course, factory, dataDir] = process.argv.slice(1);
const config = { course };
if (factory) config.factory = factory;
if (dataDir) config.dataDir = dataDir;
process.stdout.write(JSON.stringify(config, null, 2) + "\n");
' "$TUTOR_COURSE" "$TUTOR_FACTORY" "$tutor_data_dir" > "$CONFIG_DIR/config.json"
write_option() { printf '%s\t%s\n' "$1" "$2"; }
{
    write_option COURSE "$TUTOR_COURSE"
    write_option COURSE_REPO "$TUTOR_COURSE_REPO"
    write_option FACTORY "$TUTOR_FACTORY"
    write_option SELECT_RAIL "$TUTOR_SELECT_RAIL"
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
echo "Installed the Tutor plugin ${plugin_version} in ${PLUGIN_DIR}; it is path-installed into BB when the container starts."
