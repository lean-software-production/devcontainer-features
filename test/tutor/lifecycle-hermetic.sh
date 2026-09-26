#!/usr/bin/env bash
# Hermetic validation of the tutor Feature's lifecycle hooks against a fake bb
# CLI and a fake git. The real BB, plugin and clone are exercised by the
# Feature scenarios; this covers the decisions the hooks make, including
# failure paths a live container cannot easily reach.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
bb_share="$fixture/bb-share"
tutor_share="$fixture/tutor-share"
fake="$fixture/fake"
state="$fixture/state with spaces"
course="$fixture/course"
factory="$fixture/my-factory"
starter="$fixture/capstone-project-starter"
mkdir -p "$bb_share/bin" "$bb_share/npm/bin" "$tutor_share/bin" "$tutor_share/plugin/node_modules/zod" \
    "$tutor_share/plugin/dist" "$tutor_share/toolchain/toolchain-test/node_modules" "$fake/bin"

rewrite() { sed -e "s#/usr/local/share/bb#$bb_share#g" -e "s#/usr/local/share/tutor#$tutor_share#g" "$1" > "$2"; }
rewrite "$repo_root/src/bb/bin/bb-feature-common.sh" "$bb_share/bin/bb-feature-common.sh"
for name in tutor-feature-common.sh tutor-feature-bootstrap tutor-feature-autostart tutor-keepalive; do
    # A missing hook fails its own checks below rather than aborting the run.
    [ -e "$repo_root/src/tutor/bin/$name" ] || continue
    rewrite "$repo_root/src/tutor/bin/$name" "$tutor_share/bin/$name"
    chmod 755 "$tutor_share/bin/$name"
done

# CI runs this as root and exercises the production ownership checks unchanged.
# Without root, adapt only the copied fixtures' expected owner of the options.
if [ "$(id -u)" != 0 ]; then
    python3 - "$(id -u)" "$bb_share/bin/bb-feature-common.sh" BB_FEATURE_OPTIONS "$tutor_share/bin/tutor-feature-common.sh" TUTOR_FEATURE_OPTIONS <<'PY'
import pathlib, sys
uid, pairs = sys.argv[1], sys.argv[2:]
for path, variable in zip(pairs[::2], pairs[1::2]):
    p = pathlib.Path(path)
    source = p.read_text()
    original = f'[ "$(stat -c %u -- "${variable}")" = 0 ]'
    assert source.count(original) == 1, path
    p.write_text(source.replace(original, original.replace('= 0 ]', f'= {uid} ]')))
PY
fi

printf '{"name":"bb-plugin-tutor","version":"0.1.0"}\n' > "$tutor_share/plugin/package.json"
printf 'built\n' > "$tutor_share/plugin/dist/app.js"
printf '{"pins":"test"}\n' > "$tutor_share/toolchain/toolchain-test/.bb-toolchain.json"
printf '%064d\n' 1 > "$tutor_share/plugin.sha256"
copy_dir="$state/.tutor-feature/plugin-0000000000000000"

set_options() {
    local file="$1"; shift
    : > "$file"
    while [ "$#" -gt 0 ]; do printf '%s\t%s\n' "$1" "$2" >> "$file"; shift 2; done
    chmod 0644 "$file"
}
bb_options() {
    set_options "$bb_share/options.tsv" VERSION 0.43.4 MODE "${1:-standalone}" AUTOSTART "${2:-true}" \
        SERVER_PORT 48886 HOST_DAEMON_PORT 48887 DATA_DIR "$state" APP_URL auto BB_APP_BIN "$bb_share/npm/bin/bb-app"
}
default_disable=automations,workflows,tasks,github
# The starter is never cloned unless a check passes a starterRepo (the fifth argument).
tutor_options() {
    set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "${1-https://example.invalid/course.git}" \
        STARTER "$starter" STARTER_REPO "${5-}" \
        FACTORY "$factory" SELECT_OUTLINE "${2:-true}" DISABLE_PLUGINS "${3-$default_disable}" THEME "${4-plugin:tutor:paper}"
}

printf '#!/bin/sh\nexit 0\n' > "$bb_share/npm/bin/bb-app"
chmod 755 "$bb_share/npm/bin/bb-app"
cat > "$bb_share/npm/bin/bb" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
fake='$fake'
FAKE
cat >> "$bb_share/npm/bin/bb" <<'FAKE'
printf '%s\n' "$*" >> "$fake/calls.log"
printf '%s|%s|%s|%s\n' "${BB_SERVER_URL:-}" "${BB_DATA_DIR:-}" "${BB_HOST_DAEMON_PORT:-}" "${TUTOR_LEAK:-}" > "$fake/env.log"
[ ! -e "$fake/down" ] || exit 1
case "$1 $2" in
    "plugin list")
        # $fake/plugins holds "<id> <status>" lines for plugins other than tutor.
        node -e '
const fs = require("fs");
const [rootFile, statusFile, othersFile] = process.argv.slice(1);
const plugins = [];
if (fs.existsSync(rootFile) && fs.statSync(rootFile).size) {
  const status = fs.readFileSync(statusFile, "utf8").trim();
  plugins.push({ id: "tutor", rootDir: fs.readFileSync(rootFile, "utf8"), status, enabled: status !== "disabled" });
}
for (const line of fs.existsSync(othersFile) ? fs.readFileSync(othersFile, "utf8").split("\n").filter(Boolean) : []) {
  const [id, status] = line.split(" ");
  plugins.push({ id, rootDir: `/builtin/${id}`, status, enabled: status !== "disabled" });
}
console.log(JSON.stringify({ plugins }));' "$fake/plugin-root" "$fake/plugin-status" "$fake/plugins" ;;
    "plugin disable"|"plugin enable")
        [ ! -e "$fake/disable-fails" ] || { echo "disable failed" >&2; exit 1; }
        grep -q "^$3 " "$fake/plugins" 2>/dev/null || { echo "unknown plugin" >&2; exit 1; }
        [ "$2" = disable ] && next=disabled || next=running
        sed -i "s/^$3 .*/$3 $next/" "$fake/plugins" ;;
    "theme show")
        if [ "$3" = --json ]; then
            printf '{"themeId":"%s","customCss":null}\n' "$(cat "$fake/theme")"
        else
            grep -qxF "$3" "$fake/themes" 2>/dev/null || { echo "Error: HTTP 400: Invalid theme id '$3'." >&2; exit 1; }
            printf '{"id":"%s"}\n' "$3"
        fi ;;
    "theme set")
        grep -qxF "$3" "$fake/themes" 2>/dev/null || { echo "Error: HTTP 400: Invalid theme id '$3'." >&2; exit 1; }
        printf '%s' "$3" > "$fake/theme" ;;
    "plugin install")
        [ ! -e "$fake/install-fails" ] || { echo "install failed: boom" >&2; exit 1; }
        ls -d "$BB_DATA_DIR"/plugins/toolchain-* > "$fake/toolchain-at-install"
        printf '%s' "$3" > "$fake/plugin-root"
        echo running > "$fake/plugin-status" ;;
    "plugin reload")
        [ -e "$fake/reload-fails" ] || echo running > "$fake/plugin-status" ;;
    "project list")
        node -e '
const fs = require("fs");
const paths = fs.existsSync(process.argv[1]) ? fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean) : [];
console.log(JSON.stringify(paths.map((path, i) => ({ id: `proj_${i}`, sources: [{ type: "local_path", path }] }))));' "$fake/projects" ;;
    "project create") printf '%s\n' "$6" >> "$fake/projects" ;;
    "settings ui")
        case "$3" in
            get) printf '{"key":"%s","revision":0,"value":"%s"}\n' "$4" "$(cat "$fake/outline")" ;;
            set) printf '%s' "$5" > "$fake/outline" ;;
        esac ;;
    *) echo "fake bb: unexpected $*" >&2; exit 2 ;;
esac
FAKE
chmod 755 "$bb_share/npm/bin/bb"
cat > "$fake/bin/git" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$fake/git.log'
[ ! -e '$fake/git-fails' ] || exit 128
mkdir -p "\${@: -1}"
FAKE
chmod 755 "$fake/bin/git"

reset_world() {
    rm -rf "$state" "$course" "$factory" "$starter" "$fake"/{calls.log,git.log,projects,plugin-root,plugin-status,down,install-fails,reload-fails,git-fails,toolchain-at-install,disable-fails}
    mkdir -p "$state"
    printf 'thread-list/thread-list' > "$fake/outline"
    printf '%s\n' "automations running" "workflows disabled" "github running" "thread-list running" \
        "provider-codex running" "environment-git-worktree running" "keep-awake running" > "$fake/plugins"
    printf 'default' > "$fake/theme"
    # The Tutor plugin contributes its theme once it runs; model that as always available.
    printf '%s\n' default nord plugin:tutor:paper > "$fake/themes"
    bb_options; tutor_options
}
run_hook() {
    set +e
    env TUTOR_LEAK=leaked PATH="$fake/bin:$PATH" TUTOR_FEATURE_WAIT_SECONDS=2 "$tutor_share/bin/$1" > "$fixture/out" 2>&1
    rc=$?
    set -e
}
failures=0
expect() {
    local label="$1"; shift
    if "$@"; then echo "ok   $label"; else echo "FAIL $label"; sed 's/^/     | /' "$fixture/out"; failures=$((failures + 1)); fi
}
out_has() { grep -qF -- "$1" "$fixture/out"; }
calls_have() { grep -qF -- "$1" "$fake/calls.log" 2>/dev/null; }
calls_lack() { ! grep -qF -- "$1" "$fake/calls.log" 2>/dev/null; }
plugin_status() { awk -v id="$1" '$1 == id { print $2 }' "$fake/plugins"; }

# --- autostart ------------------------------------------------------------
reset_world
mkdir -p "$course"
run_hook tutor-feature-autostart
expect "first start succeeds" test "$rc" = 0
expect "plugin is installed from the digest-named copy" test "$(cat "$fake/plugin-root")" = "$copy_dir"
expect "copy links the packaged node_modules" test "$(readlink "$copy_dir/node_modules")" = "$tutor_share/plugin/node_modules"
expect "copy carries the prebuilt bundle" test -f "$copy_dir/dist/app.js"
expect "toolchain is seeded before the install" grep -qF "$state/plugins/toolchain-test" "$fake/toolchain-at-install"
expect "bb gets the bb Feature's server, state and daemon, and nothing else" \
    test "$(cat "$fake/env.log")" = "http://127.0.0.1:48886|$state|48887|"
expect "course is registered" grep -qxF "$course" "$fake/projects"
expect "missing factory is skipped" out_has "no factory at $factory yet"
expect "course outline is selected" test "$(cat "$fake/outline")" = tutor/course-outline

: > "$fake/calls.log"
mkdir -p "$factory"
run_hook tutor-feature-autostart
expect "second start succeeds" test "$rc" = 0
expect "second start does not reinstall" bash -c "! grep -q 'plugin install' '$fake/calls.log'"
expect "course is not registered twice" test "$(grep -cxF "$course" "$fake/projects")" = 1
expect "factory is registered once it exists" grep -qxF "$factory" "$fake/projects"
expect "a factory is named after its folder" calls_have "project create --name my-factory --root $factory"
expect "outline decision is made only once" bash -c "! grep -q 'settings ui' '$fake/calls.log'"

reset_world
mkdir -p "$course"
run_hook tutor-feature-autostart
echo failed > "$fake/plugin-status"; : > "$fake/calls.log"
run_hook tutor-feature-autostart
expect "a failed plugin at this build's path is reloaded" calls_have "plugin reload tutor"
expect "a reloaded plugin passes the hook" test "$rc" = 0
expect "a failed plugin is not reinstalled" bash -c "! grep -q 'plugin install' '$fake/calls.log'"

echo failed > "$fake/plugin-status"; touch "$fake/reload-fails"
run_hook tutor-feature-autostart
expect "a plugin that stays failed fails the hook" test "$rc" = 1
expect "a plugin that stays failed is explained" out_has "still 'failed' after a reload"

rm -f "$fake/reload-fails"; echo disabled > "$fake/plugin-status"; : > "$fake/calls.log"
run_hook tutor-feature-autostart
expect "a disabled plugin is left off" test "$(cat "$fake/plugin-status")" = disabled
expect "a disabled plugin is not reloaded" bash -c "! grep -q 'plugin reload' '$fake/calls.log'"
expect "a disabled plugin passes the hook" test "$rc" = 0

# The starter's factory is a dot-folder, which alone would name every factory
# ".factory"; its project is named after the codebase too.
reset_world
set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "" STARTER "$starter" STARTER_REPO "" \
    FACTORY "$starter/tetris/.factory" SELECT_OUTLINE true DISABLE_PLUGINS "" THEME ""
mkdir -p "$course" "$starter/tetris/.factory"
run_hook tutor-feature-autostart
expect "a factory inside the starter is registered" grep -qxF "$starter/tetris/.factory" "$fake/projects"
expect "a dot-folder factory is named <codebase>/<folder>" calls_have "project create --name tetris/.factory --root $starter/tetris/.factory"
expect "the starter itself is not registered" bash -c "! grep -qxF '$starter' '$fake/projects'"

reset_world
printf '/elsewhere/tutor' > "$fake/plugin-root"; echo running > "$fake/plugin-status"
mkdir -p "$state/.tutor-feature/plugin-ffffffffffffffff"
run_hook tutor-feature-autostart
expect "a plugin installed from elsewhere is replaced" test "$(cat "$fake/plugin-root")" = "$copy_dir"
expect "copies of other builds are removed" test ! -e "$state/.tutor-feature/plugin-ffffffffffffffff"

reset_world
printf 'someone/else' > "$fake/outline"
run_hook tutor-feature-autostart
expect "another thread list choice is kept" test "$(cat "$fake/outline")" = someone/else
expect "the kept choice is logged" out_has "already 'someone/else'"

reset_world
tutor_options https://example.invalid/course.git false
run_hook tutor-feature-autostart
expect "selectOutline false never touches the setting" bash -c "! grep -q 'settings ui' '$fake/calls.log'"

reset_world
mkdir -p "$course"
touch "$fake/install-fails"
run_hook tutor-feature-autostart
expect "a failed install fails the hook" test "$rc" = 1
expect "a failed install is explained" out_has "bb plugin install failed: install failed: boom"
expect "no outline is selected without the plugin" test "$(cat "$fake/outline")" = thread-list/thread-list
expect "projects are still registered" grep -qxF "$course" "$fake/projects"

reset_world
touch "$fake/down"
run_hook tutor-feature-autostart
expect "an unreachable BB fails the hook" test "$rc" = 1
expect "an unreachable BB is explained" out_has "did not answer within 2s"

reset_world
bb_options standalone false
touch "$fake/down"
run_hook tutor-feature-autostart
expect "without bb autoStart a stopped BB is not an error" test "$rc" = 0
expect "without bb autoStart the student is told what to run" out_has "then run tutor-feature-autostart"

reset_world
bb_options cli
run_hook tutor-feature-autostart
expect "cli mode is a clean no-op" test "$rc" = 0
expect "cli mode never calls bb" test ! -e "$fake/calls.log"

reset_world
chmod 0666 "$tutor_share/options.tsv"
run_hook tutor-feature-autostart
expect "options writable by others are refused" test "$rc" != 0
expect "the refusal is explained" out_has "writable by another user"

reset_world
printf 'not-a-digest\n' > "$fixture/digest"; cp "$tutor_share/plugin.sha256" "$fixture/digest.ok"; cp "$fixture/digest" "$tutor_share/plugin.sha256"
run_hook tutor-feature-autostart
expect "a malformed plugin digest is refused" out_has "plugin digest is missing or malformed"
cp "$fixture/digest.ok" "$tutor_share/plugin.sha256"

# --- switching off plugins students do not need -----------------------------
reset_world
tutor_options https://example.invalid/course.git true "automations,workflows,github,no-such-plugin,tutor,thread-list,provider-codex,environment-git-worktree"
run_hook tutor-feature-autostart
expect "disabling plugins passes the hook" test "$rc" = 0
expect "a listed running plugin is disabled" test "$(plugin_status automations)" = disabled
expect "every listed running plugin is disabled" test "$(plugin_status github)" = disabled
expect "an already disabled plugin is not disabled again" calls_lack "plugin disable workflows"
expect "an unlisted plugin is left alone" test "$(plugin_status keep-awake)" = running
expect "an unknown plugin is logged" out_has "'no-such-plugin' is not installed"
expect "tutor is never disabled" calls_lack "plugin disable tutor"
expect "the thread list is never disabled" test "$(plugin_status thread-list)" = running
expect "providers are never disabled" test "$(plugin_status provider-codex)" = running
expect "workspace environments are never disabled" test "$(plugin_status environment-git-worktree)" = running
expect "a protected plugin is refused with a reason" out_has "refusing to disable 'provider-codex'"

sed -i 's/^automations .*/automations running/' "$fake/plugins"; : > "$fake/calls.log"
run_hook tutor-feature-autostart
expect "a plugin the student re-enabled stays on" test "$(plugin_status automations)" = running
expect "each plugin is disabled only once per state directory" calls_lack "plugin disable"

tutor_options https://example.invalid/course.git true "automations,keep-awake"
run_hook tutor-feature-autostart
expect "a plugin added to the list later is disabled once" test "$(plugin_status keep-awake)" = disabled
expect "adding to the list does not re-disable earlier ones" test "$(plugin_status automations)" = running

reset_world
touch "$fake/disable-fails"
run_hook tutor-feature-autostart
expect "a failed disable fails the hook" test "$rc" = 1
expect "a failed disable is explained" out_has "cannot disable the plugin 'automations'"
rm -f "$fake/disable-fails"
run_hook tutor-feature-autostart
expect "a failed disable is retried on the next start" test "$(plugin_status automations)" = disabled

reset_world
tutor_options https://example.invalid/course.git true ""
run_hook tutor-feature-autostart
expect "an empty disablePlugins disables nothing" calls_lack "plugin disable"

reset_world
# shellcheck disable=SC2016 # the literal text is the attack
tutor_options https://example.invalid/course.git true 'automations,$(touch pwned)'
run_hook tutor-feature-autostart
expect "a malformed saved plugin id is refused" out_has "invalid saved disablePlugins"
expect "nothing is disabled with malformed options" test "$(plugin_status automations)" = running

# --- the Tutor theme ----------------------------------------------------------
reset_world
run_hook tutor-feature-autostart
expect "the Tutor theme is selected over BB's default" test "$(cat "$fake/theme")" = plugin:tutor:paper
expect "the theme choice is logged" out_has "selected the theme 'plugin:tutor:paper'"

printf 'default' > "$fake/theme"; : > "$fake/calls.log"
run_hook tutor-feature-autostart
expect "the theme is chosen only once per state directory" test "$(cat "$fake/theme")" = default
expect "no theme call after the first choice" calls_lack "theme"

reset_world
printf 'nord' > "$fake/theme"
run_hook tutor-feature-autostart
expect "a student's own theme is kept" test "$(cat "$fake/theme")" = nord
expect "the kept theme is logged" out_has "theme is already 'nord'"
printf 'default' > "$fake/theme"; : > "$fake/calls.log"
run_hook tutor-feature-autostart
expect "a kept theme still counts as the one decision" calls_lack "theme set"

reset_world
tutor_options https://example.invalid/course.git true "$default_disable" ""
run_hook tutor-feature-autostart
expect "an empty theme option never touches the theme" calls_lack "theme"

reset_world
printf '%s\n' default nord > "$fake/themes"
run_hook tutor-feature-autostart
expect "an unavailable theme does not fail the hook" test "$rc" = 0
expect "an unavailable theme is logged" out_has "theme 'plugin:tutor:paper' is not available"
expect "an unavailable theme leaves BB's theme" test "$(cat "$fake/theme")" = default
printf '%s\n' default nord plugin:tutor:paper > "$fake/themes"
run_hook tutor-feature-autostart
expect "the theme is selected once it becomes available" test "$(cat "$fake/theme")" = plugin:tutor:paper

reset_world
touch "$fake/install-fails"
run_hook tutor-feature-autostart
expect "no theme is chosen without the plugin" calls_lack "theme"

reset_world
run_hook tutor-feature-autostart
rm -f "$state/.tutor-feature/theme-selected"; printf 'default' > "$fake/theme"; echo disabled > "$fake/plugin-status"
run_hook tutor-feature-autostart
expect "no theme is chosen while the plugin is disabled" test "$(cat "$fake/theme")" = default

reset_world
tutor_options https://example.invalid/course.git true "$default_disable" 'x;y'
run_hook tutor-feature-autostart
expect "a malformed saved theme is refused" out_has "invalid saved theme"

reset_world
set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "" STARTER "starter" STARTER_REPO "" \
    FACTORY "" SELECT_OUTLINE true DISABLE_PLUGINS "" THEME ""
run_hook tutor-feature-autostart
expect "a relative saved starter is refused" out_has "unsafe saved starter path"
set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "" STARTER "" STARTER_REPO https://example.invalid/starter.git \
    FACTORY "" SELECT_OUTLINE true DISABLE_PLUGINS "" THEME ""
run_hook tutor-feature-autostart
expect "a saved starterRepo without a starter is refused" out_has "unsafe saved starterRepo"
set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "" STARTER "$course" STARTER_REPO "" \
    FACTORY "" SELECT_OUTLINE true DISABLE_PLUGINS "" THEME ""
run_hook tutor-feature-autostart
expect "a saved starter equal to the course is refused" out_has "saved starter is the course"

# --- keep-alive ---------------------------------------------------------------
activity="$state/.tutor-feature/activity"
run_keepalive() {
    set +e
    env PATH="$fake/bin:$PATH" "$@" > "$fixture/out" 2>&1
    rc=$?
    set -e
}
reset_world
mkdir -p "$state/.tutor-feature"
date -u +%FT%T.123Z > "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "keep-alive reports fresh BB activity" out_has "you're active in BB"
expect "keep-alive prints exactly one line per check" bash -c "test \"\$(wc -l < '$fixture/out')\" = 1 && grep -q 'keeping this Codespace awake' '$fixture/out'"

date -u -d '-121 seconds' +%FT%TZ > "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "keep-alive is silent for stale activity" test ! -s "$fixture/out"
date -u -d '-100 seconds' +%FT%TZ > "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "activity within 120 s counts" out_has "you're active in BB"
rm -f "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "keep-alive is silent without an activity file" test ! -s "$fixture/out"
printf 'yesterday\n' > "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "keep-alive is silent for a malformed timestamp" test ! -s "$fixture/out"
date -u -d '+1 hour' +%FT%TZ > "$activity"
run_keepalive "$tutor_share/bin/tutor-keepalive" --once
expect "keep-alive ignores a timestamp in the future" test ! -s "$fixture/out"

run_keepalive env -u CODESPACES -u TUTOR_KEEPALIVE_FORCE "$tutor_share/bin/tutor-keepalive"
expect "outside a Codespace keep-alive returns at once" test "$rc" = 0
expect "outside a Codespace keep-alive says why" out_has "only runs in a GitHub Codespace"
run_keepalive env CODESPACES=true "$tutor_share/bin/tutor-keepalive"
expect "without a terminal keep-alive returns at once" test "$rc" = 0
expect "without a terminal keep-alive says why" out_has "not a terminal"

# A Codespace attach terminal is a pty: there the loop keeps running.
date -u +%FT%TZ > "$activity"
run_keepalive env -u TUTOR_KEEPALIVE_FORCE CODESPACES=true TUTOR_KEEPALIVE_INTERVAL=1 \
    script -qec "timeout 3 '$tutor_share/bin/tutor-keepalive'" /dev/null
expect "in a Codespace terminal keep-alive keeps running" test "$rc" = 124
expect "in a Codespace terminal keep-alive announces itself" out_has "keep-alive is on"
expect "in a Codespace terminal keep-alive reports activity" out_has "you're active in BB"

env PATH="$fake/bin:$PATH" TUTOR_KEEPALIVE_FORCE=1 TUTOR_KEEPALIVE_INTERVAL=1 \
    "$tutor_share/bin/tutor-keepalive" > "$fixture/first.out" 2>&1 &
first=$!
for _ in $(seq 1 50); do grep -q "active in BB" "$fixture/first.out" 2>/dev/null && break; sleep 0.1; done
expect "the loop reports activity" grep -q "you're active in BB" "$fixture/first.out"
run_keepalive env TUTOR_KEEPALIVE_FORCE=1 TUTOR_KEEPALIVE_INTERVAL=1 timeout 5 "$tutor_share/bin/tutor-keepalive"
expect "a second keep-alive exits at once" test "$rc" = 0
expect "a second keep-alive says one is already running" out_has "already running"
expect "a second keep-alive never reports activity" bash -c "! grep -q 'active in BB' '$fixture/out'"
kill "$first" 2>/dev/null || true; wait "$first" 2>/dev/null || true
run_keepalive env TUTOR_KEEPALIVE_FORCE=1 TUTOR_KEEPALIVE_INTERVAL=1 timeout 2 "$tutor_share/bin/tutor-keepalive"
expect "a new keep-alive can start once the old one is gone" out_has "you're active in BB"

# --- bootstrap ------------------------------------------------------------
reset_world
run_hook tutor-feature-bootstrap
expect "bootstrap clones a missing course" test "$rc" = 0
expect "clone never takes options from the URL" test "$(cat "$fake/git.log")" = "clone --quiet -- https://example.invalid/course.git $course"

reset_world
mkdir -p "$course"
run_hook tutor-feature-bootstrap
expect "an existing course is not cloned over" test ! -e "$fake/git.log"

reset_world
tutor_options ""
run_hook tutor-feature-bootstrap
expect "empty courseRepo never clones" test ! -e "$fake/git.log"

reset_world
touch "$fake/git-fails"
run_hook tutor-feature-bootstrap
expect "a failed clone does not fail the hook" test "$rc" = 0
expect "a failed clone says how to recover" out_has "clone it yourself with: git clone https://example.invalid/course.git $course"

reset_world
set_options "$tutor_share/options.tsv" COURSE "/nonexistent-parent-$$/course" COURSE_REPO https://example.invalid/course.git \
    STARTER "" STARTER_REPO "" FACTORY "" SELECT_OUTLINE true DISABLE_PLUGINS "" THEME ""
run_hook tutor-feature-bootstrap
expect "an unwritable parent is reported, not fatal" test "$rc" = 0
expect "no clone is attempted into an unwritable parent" test ! -e "$fake/git.log"

# The starter is cloned like the course, and independently of it.
reset_world
mkdir -p "$course"
tutor_options https://example.invalid/course.git true "$default_disable" plugin:tutor:paper https://example.invalid/starter.git
run_hook tutor-feature-bootstrap
expect "bootstrap clones a missing starter" test "$rc" = 0
expect "the starter clone never takes options from the URL" test "$(cat "$fake/git.log")" = "clone --quiet -- https://example.invalid/starter.git $starter"

reset_world
tutor_options https://example.invalid/course.git true "$default_disable" plugin:tutor:paper https://example.invalid/starter.git
run_hook tutor-feature-bootstrap
expect "a missing course and starter are both cloned" \
    test "$(cat "$fake/git.log")" = "clone --quiet -- https://example.invalid/course.git $course"$'\n'"clone --quiet -- https://example.invalid/starter.git $starter"

reset_world
mkdir -p "$course" "$starter"
tutor_options https://example.invalid/course.git true "$default_disable" plugin:tutor:paper https://example.invalid/starter.git
run_hook tutor-feature-bootstrap
expect "an existing starter is not cloned over" test ! -e "$fake/git.log"
expect "an existing starter is logged" out_has "starter found at $starter"

reset_world
mkdir -p "$course"
run_hook tutor-feature-bootstrap
expect "empty starterRepo never clones" test ! -e "$fake/git.log"

reset_world
mkdir -p "$course"
tutor_options https://example.invalid/course.git true "$default_disable" plugin:tutor:paper https://example.invalid/starter.git
touch "$fake/git-fails"
run_hook tutor-feature-bootstrap
expect "a failed starter clone does not fail the hook" test "$rc" = 0
expect "a failed starter clone says how to recover" out_has "clone it yourself with: git clone https://example.invalid/starter.git $starter"

reset_world
tutor_options https://example.invalid/course.git true "$default_disable" plugin:tutor:paper https://example.invalid/starter.git
touch "$fake/git-fails"
run_hook tutor-feature-bootstrap
expect "a failed course clone still tries the starter" grep -qxF "clone --quiet -- https://example.invalid/starter.git $starter" "$fake/git.log"

[ "$failures" -eq 0 ] || { echo "$failures tutor lifecycle check(s) failed" >&2; exit 1; }
echo 'tutor hermetic lifecycle checks passed'
