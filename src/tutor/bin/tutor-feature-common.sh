#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Shared, non-secret runtime helpers for the tutor Feature's lifecycle hooks.
# Builds on the bb Feature's helpers; never sources user-controlled files.
set -euo pipefail
# shellcheck source=../../bb/bin/bb-feature-common.sh
. /usr/local/share/bb/bin/bb-feature-common.sh

TUTOR_FEATURE_SHARE=/usr/local/share/tutor
TUTOR_FEATURE_OPTIONS="$TUTOR_FEATURE_SHARE/options.tsv"
# Read by the hooks that source this file.
# shellcheck disable=SC2034
{
    TUTOR_FEATURE_PLUGIN_DIR="$TUTOR_FEATURE_SHARE/plugin"
    TUTOR_FEATURE_TOOLCHAIN_DIR="$TUTOR_FEATURE_SHARE/toolchain"
    TUTOR_FEATURE_PLUGIN_DIGEST="$TUTOR_FEATURE_SHARE/plugin.sha256"
    TUTOR_PLUGIN_ID=tutor
    TUTOR_DEFAULT_THREAD_LIST=thread-list/thread-list
    TUTOR_RAIL_THREAD_LIST=tutor/course-rail
    TUTOR_DEFAULT_THEME=default
    # One line: the ISO-8601 UTC time a student last used BB, written by the
    # plugin. Relative to the runtime directory.
    TUTOR_ACTIVITY_FILE=activity
    TUTOR_ACTIVITY_WINDOW_SECONDS=120
}

tutor_log() {
    printf 'tutor Feature: %s\n' "$*" >&2
    if [ -n "${TUTOR_FEATURE_LOG:-}" ]; then printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$TUTOR_FEATURE_LOG"; fi
}
tutor_fail() { tutor_log "ERROR: $*"; return 1; }

tutor_option() {
    local wanted="$1" key value
    [ -f "$TUTOR_FEATURE_OPTIONS" ] && [ ! -L "$TUTOR_FEATURE_OPTIONS" ] || { tutor_fail "Feature options are missing or unsafe."; return 1; }
    [ "$(stat -c %u -- "$TUTOR_FEATURE_OPTIONS")" = 0 ] || { tutor_fail "Feature options are not owned by root."; return 1; }
    [ $((8#$(stat -c %a -- "$TUTOR_FEATURE_OPTIONS") & 022)) -eq 0 ] || { tutor_fail "Feature options are writable by another user."; return 1; }
    while IFS=$'\t' read -r key value; do
        [ "$key" = "$wanted" ] && { printf '%s' "$value"; return 0; }
    done < "$TUTOR_FEATURE_OPTIONS"
    tutor_fail "Feature option $wanted is missing."
}

tutor_safe_path() {
    [[ "$1" = /?* ]] && ! bb_feature_unsafe "$1" && [[ "$1" != *\"* && "$1" != *\\* ]] \
        && [[ "/$1/" != *'/./'* && "/$1/" != *'/../'* ]]
}

# A BB plugin id, as the plugin CLI accepts it.
tutor_plugin_id() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }
# A comma-separated list of plugin ids with no empty items.
tutor_plugin_list() {
    local id
    local -a ids
    [ -n "$1" ] || return 0
    [[ "$1" != *, && "$1" != ,* && "$1" != *,,* ]] || return 1
    IFS=, read -r -a ids <<< "$1"
    for id in "${ids[@]}"; do tutor_plugin_id "$id" || return 1; done
}
# Plugins Tutor runs on: the plugin itself, the sidebar, the agent providers
# and the workspace environments coach threads use.
tutor_protected_plugin() {
    case "$1" in
        tutor|thread-list|provider-*|environment-project-checkout|environment-personal-workspace|environment-git-worktree) return 0 ;;
    esac
    return 1
}
# A built-in, custom or plugin theme id, as `bb theme set` takes it.
tutor_theme_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9:._-]*$ ]]; }

tutor_validate_options() {
    TUTOR_COURSE="$(tutor_option COURSE)"
    TUTOR_COURSE_REPO="$(tutor_option COURSE_REPO)"
    TUTOR_FACTORY="$(tutor_option FACTORY)"
    TUTOR_SELECT_RAIL="$(tutor_option SELECT_RAIL)"
    TUTOR_DISABLE_PLUGINS="$(tutor_option DISABLE_PLUGINS)"
    TUTOR_THEME="$(tutor_option THEME)"
    tutor_safe_path "$TUTOR_COURSE" || { tutor_fail "unsafe saved course path"; return 1; }
    [ -z "$TUTOR_FACTORY" ] || tutor_safe_path "$TUTOR_FACTORY" || { tutor_fail "unsafe saved factory path"; return 1; }
    [ -z "$TUTOR_COURSE_REPO" ] || { [[ "$TUTOR_COURSE_REPO" = https://* ]] && ! bb_feature_unsafe "$TUTOR_COURSE_REPO"; } || { tutor_fail "unsafe saved courseRepo"; return 1; }
    case "$TUTOR_SELECT_RAIL" in true|false) ;; *) tutor_fail "invalid saved selectRail"; return 1 ;; esac
    tutor_plugin_list "$TUTOR_DISABLE_PLUGINS" || { tutor_fail "invalid saved disablePlugins"; return 1; }
    [ -z "$TUTOR_THEME" ] || tutor_theme_id "$TUTOR_THEME" || { tutor_fail "invalid saved theme"; return 1; }
}

# Requires bb_feature_validate_options and bb_feature_prepare_data_dir. Creates
# the Feature's own user-owned runtime directory beside the bb Feature's.
tutor_prepare_runtime_dir() {
    TUTOR_FEATURE_RUNTIME_DIR="$BB_FEATURE_DATA_DIR/.tutor-feature"
    [ -d "$TUTOR_FEATURE_RUNTIME_DIR" ] || mkdir -m 0700 -- "$TUTOR_FEATURE_RUNTIME_DIR"
    [ -d "$TUTOR_FEATURE_RUNTIME_DIR" ] && [ ! -L "$TUTOR_FEATURE_RUNTIME_DIR" ] || { tutor_fail "runtime directory is not a real directory"; return 1; }
    [ "$(stat -c %u -- "$TUTOR_FEATURE_RUNTIME_DIR")" = "$(id -u)" ] || { tutor_fail "runtime directory is not owned by the remote user"; return 1; }
    chmod 0700 -- "$TUTOR_FEATURE_RUNTIME_DIR"
}

# The bb Feature does not export these, so every bb CLI call gets them from the
# bb Feature's validated options, in a clean environment.
tutor_bb() {
    bb_feature_clean_env \
        BB_SERVER_URL="http://127.0.0.1:${BB_FEATURE_SERVER_PORT}" \
        BB_DATA_DIR="$BB_FEATURE_DATA_DIR" \
        BB_HOST_DAEMON_PORT="$BB_FEATURE_DAEMON_PORT" \
        "$(dirname "$BB_FEATURE_APP_BIN")/bb" "$@"
}

# Reads JSON on stdin and prints what the named query returns (empty when
# absent). Queries take one argument.
tutor_json() {
    # shellcheck disable=SC2016 # JavaScript, not shell
    node -e '
const [query, arg] = process.argv.slice(1);
let input = "";
process.stdin.on("data", (d) => (input += d)).on("end", () => {
  const data = JSON.parse(input);
  const out = {
    // `bb plugin list --json`: "<rootDir>\t<status>" of plugin <arg>.
    plugin: () => {
      const p = (data.plugins || []).find((x) => x.id === arg);
      return p ? `${p.rootDir || ""}\t${p.status || ""}` : "";
    },
    // `bb plugin list --json`: "<id>\tenabled|disabled" lines for every plugin.
    "plugin-states": () =>
      (data.plugins || []).map((p) => `${p.id}\t${p.enabled === false ? "disabled" : "enabled"}\n`).join(""),
    // `bb theme show --json`: the active theme id.
    theme: () => (typeof data.themeId === "string" ? data.themeId : ""),
    // `bb project list --json`: "yes" when a local source has path <arg>.
    project: () =>
      data.some((p) => (p.sources || []).some((s) => s.type === "local_path" && s.path === arg)) ? "yes" : "",
    // `bb settings ui get <key> --json`: the value.
    value: () => (typeof data.value === "string" ? data.value : JSON.stringify(data.value)),
  }[query];
  if (!out) throw new Error(`unknown query ${query}`);
  process.stdout.write(out());
});' "$1" "${2:-}"
}
