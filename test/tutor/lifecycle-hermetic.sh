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
mkdir -p "$bb_share/bin" "$bb_share/npm/bin" "$tutor_share/bin" "$tutor_share/plugin/node_modules/zod" \
    "$tutor_share/plugin/dist" "$tutor_share/toolchain/toolchain-test/node_modules" "$fake/bin"

rewrite() { sed -e "s#/usr/local/share/bb#$bb_share#g" -e "s#/usr/local/share/tutor#$tutor_share#g" "$1" > "$2"; }
rewrite "$repo_root/src/bb/bin/bb-feature-common.sh" "$bb_share/bin/bb-feature-common.sh"
for name in tutor-feature-common.sh tutor-feature-bootstrap tutor-feature-autostart; do
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
tutor_options() {
    set_options "$tutor_share/options.tsv" COURSE "$course" COURSE_REPO "${1-https://example.invalid/course.git}" \
        FACTORY "$factory" SELECT_RAIL "${2:-true}"
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
        if [ -s "$fake/plugin-root" ]; then
            printf '{"plugins":[{"id":"tutor","rootDir":"%s","status":"%s"}]}\n' "$(cat "$fake/plugin-root")" "$(cat "$fake/plugin-status")"
        else
            echo '{"plugins":[]}'
        fi ;;
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
            get) printf '{"key":"%s","revision":0,"value":"%s"}\n' "$4" "$(cat "$fake/rail")" ;;
            set) printf '%s' "$5" > "$fake/rail" ;;
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
    rm -rf "$state" "$course" "$factory" "$fake"/{calls.log,git.log,projects,plugin-root,plugin-status,down,install-fails,reload-fails,git-fails,toolchain-at-install}
    mkdir -p "$state"
    printf 'thread-list/thread-list' > "$fake/rail"
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
expect "course rail is selected" test "$(cat "$fake/rail")" = tutor/course-rail

: > "$fake/calls.log"
mkdir -p "$factory"
run_hook tutor-feature-autostart
expect "second start succeeds" test "$rc" = 0
expect "second start does not reinstall" bash -c "! grep -q 'plugin install' '$fake/calls.log'"
expect "course is not registered twice" test "$(grep -cxF "$course" "$fake/projects")" = 1
expect "factory is registered once it exists" grep -qxF "$factory" "$fake/projects"
expect "rail decision is made only once" bash -c "! grep -q 'settings ui' '$fake/calls.log'"

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

reset_world
printf '/elsewhere/tutor' > "$fake/plugin-root"; echo running > "$fake/plugin-status"
mkdir -p "$state/.tutor-feature/plugin-ffffffffffffffff"
run_hook tutor-feature-autostart
expect "a plugin installed from elsewhere is replaced" test "$(cat "$fake/plugin-root")" = "$copy_dir"
expect "copies of other builds are removed" test ! -e "$state/.tutor-feature/plugin-ffffffffffffffff"

reset_world
printf 'someone/else' > "$fake/rail"
run_hook tutor-feature-autostart
expect "another thread list choice is kept" test "$(cat "$fake/rail")" = someone/else
expect "the kept choice is logged" out_has "already 'someone/else'"

reset_world
tutor_options https://example.invalid/course.git false
run_hook tutor-feature-autostart
expect "selectRail false never touches the setting" bash -c "! grep -q 'settings ui' '$fake/calls.log'"

reset_world
mkdir -p "$course"
touch "$fake/install-fails"
run_hook tutor-feature-autostart
expect "a failed install fails the hook" test "$rc" = 1
expect "a failed install is explained" out_has "bb plugin install failed: install failed: boom"
expect "no rail is selected without the plugin" test "$(cat "$fake/rail")" = thread-list/thread-list
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
set_options "$tutor_share/options.tsv" COURSE "/nonexistent-parent-$$/course" COURSE_REPO https://example.invalid/course.git FACTORY "" SELECT_RAIL true
run_hook tutor-feature-bootstrap
expect "an unwritable parent is reported, not fatal" test "$rc" = 0
expect "no clone is attempted into an unwritable parent" test ! -e "$fake/git.log"

[ "$failures" -eq 0 ] || { echo "$failures tutor lifecycle check(s) failed" >&2; exit 1; }
echo 'tutor hermetic lifecycle checks passed'
