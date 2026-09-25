#!/usr/bin/env bash
# Shared, non-secret runtime helpers. Never source user-controlled files.
set -euo pipefail

BB_FEATURE_SHARE=/usr/local/share/bb
BB_FEATURE_OPTIONS="${BB_FEATURE_SHARE}/options.tsv"

bb_feature_fail() { echo "ERROR: bb Feature: $*" >&2; return 1; }

bb_feature_option() {
    local wanted="$1" key value
    [ -f "$BB_FEATURE_OPTIONS" ] && [ ! -L "$BB_FEATURE_OPTIONS" ] || { bb_feature_fail "Feature options are missing or unsafe."; return 1; }
    [ "$(stat -c %u -- "$BB_FEATURE_OPTIONS")" = 0 ] || { bb_feature_fail "Feature options are not owned by root."; return 1; }
    [ $((8#$(stat -c %a -- "$BB_FEATURE_OPTIONS") & 022)) -eq 0 ] || { bb_feature_fail "Feature options are writable by another user."; return 1; }
    while IFS=$'\t' read -r key value; do
        [ "$key" = "$wanted" ] && { printf '%s' "$value"; return 0; }
    done < "$BB_FEATURE_OPTIONS"
    bb_feature_fail "Feature option $wanted is missing."
}

bb_feature_unsafe() { [[ "$1" =~ [[:cntrl:]] ]] || [[ "$1" == *';'* || "$1" == *'|'* || "$1" == *'&'* || "$1" == *'$'* || "$1" == *'`'* || "$1" == *'<'* || "$1" == *'>'* ]]; }
bb_feature_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]; }

bb_feature_validate_options() {
    BB_FEATURE_MODE="$(bb_feature_option MODE)"
    BB_FEATURE_AUTOSTART="$(bb_feature_option AUTOSTART)"
    BB_FEATURE_SERVER_PORT="$(bb_feature_option SERVER_PORT)"
    BB_FEATURE_DAEMON_PORT="$(bb_feature_option HOST_DAEMON_PORT)"
    BB_FEATURE_RAW_DATA_DIR="$(bb_feature_option DATA_DIR)"
    BB_FEATURE_APP_URL_OPTION="$(bb_feature_option APP_URL)"
    BB_FEATURE_APP_BIN="$(bb_feature_option BB_APP_BIN)"
    case "$BB_FEATURE_MODE" in cli|standalone) ;; *) bb_feature_fail "invalid saved mode"; return 1;; esac
    case "$BB_FEATURE_AUTOSTART" in true|false) ;; *) bb_feature_fail "invalid saved autoStart"; return 1;; esac
    bb_feature_port "$BB_FEATURE_SERVER_PORT" && bb_feature_port "$BB_FEATURE_DAEMON_PORT" && [ "$BB_FEATURE_SERVER_PORT" != "$BB_FEATURE_DAEMON_PORT" ] || { bb_feature_fail "invalid saved ports"; return 1; }
    [ -x "$BB_FEATURE_APP_BIN" ] && [[ "$BB_FEATURE_APP_BIN" = "${BB_FEATURE_SHARE}/npm/bin/bb-app" ]] || { bb_feature_fail "packaged bb-app launcher is missing or unexpected"; return 1; }
    [ -z "$BB_FEATURE_RAW_DATA_DIR" ] || { [[ "$BB_FEATURE_RAW_DATA_DIR" = /* ]] && ! bb_feature_unsafe "$BB_FEATURE_RAW_DATA_DIR"; } || { bb_feature_fail "unsafe saved dataDir"; return 1; }
    [ "$BB_FEATURE_APP_URL_OPTION" = auto ] || ! bb_feature_unsafe "$BB_FEATURE_APP_URL_OPTION" || { bb_feature_fail "unsafe saved appUrl"; return 1; }
}

bb_feature_data_dir() {
    if [ -n "$BB_FEATURE_RAW_DATA_DIR" ]; then printf '%s' "$BB_FEATURE_RAW_DATA_DIR"; else printf '%s/.bb' "$HOME"; fi
}

bb_feature_no_symlink_ancestors() {
    # realpath resolves symlinks, so comparing two realpath results cannot
    # establish that the lexical path was symlink-free. Check every existing
    # component before *and* after mkdir -p instead. Dot traversal is refused
    # so the path we inspect is exactly the path we later create/use.
    local target="$1" component candidate=/
    local -a components
    [[ "$target" = /* ]] || { bb_feature_fail "data directory must be absolute"; return 1; }
    IFS=/ read -r -a components <<< "${target#/}"
    for component in "${components[@]}"; do
        [ -n "$component" ] || continue
        case "$component" in
            .|..) bb_feature_fail "data directory must not contain dot traversal"; return 1 ;;
        esac
        candidate="${candidate%/}/$component"
        [ ! -L "$candidate" ] || { bb_feature_fail "data directory or an ancestor is a symlink; choose a non-symlink path"; return 1; }
    done
}

bb_feature_prepare_data_dir() {
    BB_FEATURE_DATA_DIR="$(bb_feature_data_dir)"
    [[ "$BB_FEATURE_DATA_DIR" = /* ]] || { bb_feature_fail "data directory must be absolute"; return 1; }
    bb_feature_no_symlink_ancestors "$BB_FEATURE_DATA_DIR"
    mkdir -p -m 0700 -- "$BB_FEATURE_DATA_DIR"
    # Detect an ancestor swapped while mkdir -p was running as well as links
    # that existed before it. Do not use realpath here: it follows the very
    # link this check is meant to reject.
    bb_feature_no_symlink_ancestors "$BB_FEATURE_DATA_DIR"
    [ -d "$BB_FEATURE_DATA_DIR" ] && [ ! -L "$BB_FEATURE_DATA_DIR" ] || { bb_feature_fail "data directory is not a real directory"; return 1; }
    local owner
    owner="$(stat -c %u -- "$BB_FEATURE_DATA_DIR")"
    [ "$owner" = "$(id -u)" ] || { bb_feature_fail "data directory is owned by uid $owner, not the remote user"; return 1; }
    chmod 0700 -- "$BB_FEATURE_DATA_DIR"
    mkdir -p -m 0700 -- "$BB_FEATURE_DATA_DIR/.bb-feature"
    [ ! -L "$BB_FEATURE_DATA_DIR/.bb-feature" ] || { bb_feature_fail "feature runtime directory is a symlink"; return 1; }
    owner="$(stat -c %u -- "$BB_FEATURE_DATA_DIR/.bb-feature")"
    [ "$owner" = "$(id -u)" ] || { bb_feature_fail "feature runtime directory is not owned by the remote user"; return 1; }
    chmod 0700 -- "$BB_FEATURE_DATA_DIR/.bb-feature"
    BB_FEATURE_RUNTIME_DIR="$BB_FEATURE_DATA_DIR/.bb-feature"
}

bb_feature_origin() {
    local value="$BB_FEATURE_APP_URL_OPTION"
    if [ "$value" = auto ]; then
        if [ -n "${CODESPACE_NAME:-}" ]; then
            [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ] || { bb_feature_fail "Codespaces was detected but GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN is missing; set appUrl explicitly."; return 1; }
            [[ "$CODESPACE_NAME" =~ ^[A-Za-z0-9-]+$ ]] && [[ "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { bb_feature_fail "Codespaces URL variables contain unsafe characters; set appUrl explicitly."; return 1; }
            value="https://${CODESPACE_NAME}-${BB_FEATURE_SERVER_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
        else
            value="http://127.0.0.1:${BB_FEATURE_SERVER_PORT}"
        fi
    fi
    ! bb_feature_unsafe "$value" || { bb_feature_fail "appUrl contains unsafe characters"; return 1; }
    node -e 'const v=process.argv[1]; let u; try { u=new URL(v); } catch { process.exit(2); } if (!/^https?:$/.test(u.protocol)||u.origin!==v||u.username||u.password) process.exit(2);' "$value" || { bb_feature_fail "appUrl must be an http(s) origin with no path, query, fragment, or credentials"; return 1; }
    printf '%s' "$value"
}

bb_feature_clean_env() {
    env -i HOME="$HOME" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-$(id -un)}" PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$@"
}

bb_feature_apply_origin() {
    BB_FEATURE_ORIGIN="$(bb_feature_origin)"
    bb_feature_clean_env "$BB_FEATURE_APP_BIN" --data-dir "$BB_FEATURE_DATA_DIR" \
        --server-port "$BB_FEATURE_SERVER_PORT" --host-daemon-port "$BB_FEATURE_DAEMON_PORT" \
        config set BB_APP_URL "$BB_FEATURE_ORIGIN" >/dev/null
    printf '%s\t%s\n' APP_URL "$BB_FEATURE_ORIGIN" > "$BB_FEATURE_RUNTIME_DIR/config.tsv"
    chmod 0600 "$BB_FEATURE_RUNTIME_DIR/config.tsv"
}

bb_feature_health() {
    curl --fail --silent --show-error --max-time 2 "http://127.0.0.1:${BB_FEATURE_SERVER_PORT}/health" >/dev/null 2>&1
}

bb_feature_daemon_ready() {
    # BB's HTTP server can become healthy before its local host daemon starts.
    # Probe only the configured loopback helper; never forward or bind it here.
    timeout 2 node - "$BB_FEATURE_DAEMON_PORT" <<'JS' >/dev/null 2>&1
const net = require('node:net');
const socket = net.connect({ host: '127.0.0.1', port: Number(process.argv[2]) });
const timer = setTimeout(() => finish(1), 1000);
function finish(code) {
    clearTimeout(timer);
    socket.destroy();
    process.exit(code);
}
socket.once('connect', () => finish(0));
socket.once('error', () => finish(1));
JS
}

bb_feature_ready() {
    # Check HTTP after the daemon is reachable, rather than reusing a health
    # result obtained before daemon startup has begun.
    bb_feature_daemon_ready && bb_feature_health
}

bb_feature_wait_ready() {
    local launcher_pid="$1" wait_seconds="${2:-30}" deadline
    deadline=$((SECONDS + wait_seconds))
    while [ "$SECONDS" -lt "$deadline" ]; do
        kill -0 "$launcher_pid" 2>/dev/null || return 1
        bb_feature_ready && return 0
        sleep 1
    done
    return 1
}

bb_feature_read_runtime() {
    local bb_feature_runtime_file="$BB_FEATURE_RUNTIME_DIR/launcher.tsv"
    [ -e "$bb_feature_runtime_file" ] || return 1
    [ -f "$bb_feature_runtime_file" ] && [ ! -L "$bb_feature_runtime_file" ] || { bb_feature_fail "runtime record is unsafe"; return 2; }
    [ "$(stat -c %u -- "$bb_feature_runtime_file")" = "$(id -u)" ] || { bb_feature_fail "runtime record is not owned by the remote user"; return 2; }
    [ $((8#$(stat -c %a -- "$bb_feature_runtime_file") & 022)) -eq 0 ] || { bb_feature_fail "runtime record is writable by another user"; return 2; }
    local key value
    BB_FEATURE_PID= BB_FEATURE_PID_UID= BB_FEATURE_PID_BIN= BB_FEATURE_PID_DATA=
    while IFS=$'\t' read -r key value; do
        case "$key" in PID) BB_FEATURE_PID="$value";; UID) BB_FEATURE_PID_UID="$value";; BIN) BB_FEATURE_PID_BIN="$value";; DATA_DIR) BB_FEATURE_PID_DATA="$value";; esac
    done < "$bb_feature_runtime_file"
    [[ "$BB_FEATURE_PID" =~ ^[0-9]+$ ]] && [ "$BB_FEATURE_PID_UID" = "$(id -u)" ] && [ "$BB_FEATURE_PID_BIN" = "$BB_FEATURE_APP_BIN" ] && [ "$BB_FEATURE_PID_DATA" = "$BB_FEATURE_DATA_DIR" ]
}

bb_feature_owned_launcher_alive() {
    bb_feature_read_runtime || return $?
    kill -0 "$BB_FEATURE_PID" 2>/dev/null || return 1
    [ "$(stat -c %u -- "/proc/$BB_FEATURE_PID")" = "$(id -u)" ] || return 1
    local command_line
    command_line="$(tr '\000' ' ' < "/proc/$BB_FEATURE_PID/cmdline" 2>/dev/null || true)"
    [[ "$command_line" == *"$BB_FEATURE_APP_BIN"* ]] && [[ "$command_line" == *"--data-dir $BB_FEATURE_DATA_DIR"* ]]
}

bb_feature_write_runtime() {
    local bb_feature_runtime_file="$BB_FEATURE_RUNTIME_DIR/launcher.tsv"
    umask 077
    { printf 'PID\t%s\nUID\t%s\nBIN\t%s\nDATA_DIR\t%s\n' "$1" "$(id -u)" "$BB_FEATURE_APP_BIN" "$BB_FEATURE_DATA_DIR"; } > "$bb_feature_runtime_file"
    chmod 0600 "$bb_feature_runtime_file"
}
