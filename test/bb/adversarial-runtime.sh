#!/usr/bin/env bash
# Hermetic lifecycle validation with a tiny local launcher double. The real npm
# package is exercised by Feature scenarios; this covers hostile state paths
# and the server/daemon readiness race using actual loopback sockets.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
share="$fixture/share"
state="$fixture/state with spaces"
cleanup() {
  local record pid
  for record in "$fixture"/*/.bb-feature/launcher.tsv; do
    [ -f "$record" ] || continue
    pid="$(awk -F '\t' '$1=="PID"{print $2}' "$record")"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  done
  [ -z "${conflict:-}" ] || kill "$conflict" 2>/dev/null || true
  rm -rf "$fixture"
}
trap cleanup EXIT
mkdir -p "$share/bin" "$share/npm/bin" "$state"

for name in bb-feature-common.sh bb-feature-bootstrap bb-feature-autostart bb-feature-status; do
    sed "s#/usr/local/share/bb#$share#g" "$repo_root/src/bb/bin/$name" > "$share/bin/$name"
    chmod 755 "$share/bin/$name"
done

# CI runs as root and exercises the production ownership check unchanged.
# Without root, adapt only the copied fixture's expected metadata owner to the
# test user; no installed helper or production ownership policy is changed.
if [ "$(id -u)" != 0 ]; then
  python3 - "$share/bin/bb-feature-common.sh" "$(id -u)" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
source = p.read_text()
original = '[ "$(stat -c %u -- "$BB_FEATURE_OPTIONS")" = 0 ]'
assert source.count(original) == 1
p.write_text(source.replace(original, original.replace('= 0 ]', '= ' + sys.argv[2] + ' ]')))
PY
fi

cat > "$share/npm/bin/bb-app" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
data= port= daemon=
args=" $* "
origin="${!#}"
while [ "$#" -gt 0 ]; do
  case "$1" in --data-dir) data="$2"; shift 2;; --server-port) port="$2"; shift 2;; --host-daemon-port) daemon="$2"; shift 2;; *) shift;; esac
done
if [[ "$args" == *' config set '* ]]; then
  mkdir -p "$data"
  printf '{"config":{"BB_APP_URL":"%s"}}\n' "$origin" > "$data/config.json"
  exit 0
fi
python3 - "$port" "$daemon" "$data" <<'PY' &
import http.server, pathlib, socket, socketserver, sys, threading, time
data = pathlib.Path(sys.argv[3])
delay = float((data / 'daemon-delay').read_text()) if (data / 'daemon-delay').exists() else 0
ready_after = time.monotonic() + delay
def paused():
 return time.monotonic() < ready_after or (data / 'daemon-pause').exists() or (data / 'daemon-never').exists()
def daemon():
 while True:
  if paused():
   time.sleep(.05); continue
  with socket.socket() as listener:
   listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
   listener.bind(('127.0.0.1', int(sys.argv[2])))
   listener.listen(); listener.settimeout(.1)
   while not paused():
    try:
     connection, _ = listener.accept(); connection.close()
    except socket.timeout:
     pass
threading.Thread(target=daemon, daemon=True).start()
class H(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  once = data / 'health-timeout-once'
  if once.exists():
   once.unlink()
   # Exceed the unchanged two-second curl deadline on exactly one request.
   time.sleep(2.5)
  self.send_response(503 if (data / 'server-unhealthy').exists() else 200)
  self.end_headers()
  try: self.wfile.write(b'{"ok":true}')
  except BrokenPipeError: pass
 def log_message(self, *a): pass
class Server(socketserver.TCPServer): allow_reuse_address = True
Server(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
child=$!
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 0' TERM INT
wait "$child"
FAKE
chmod 755 "$share/npm/bin/bb-app"

write_options() {
  local port="$1" daemon="$2" app_url="$3" data_dir="$4"
  cat > "$share/options.tsv" <<EOF
VERSION	0.43.3
MODE	standalone
AUTOSTART	true
SERVER_PORT	$port
HOST_DAEMON_PORT	$daemon
DATA_DIR	$data_dir
APP_URL	$app_url
BB_APP_BIN	$share/npm/bin/bb-app
EOF
  if [ "$(id -u)" = 0 ]; then chown root:root "$share/options.tsv"; fi
  chmod 644 "$share/options.tsv"
}

# Force GNU setsid's intermediate-fork path so the PID handoff is exercised,
# then terminate the lifecycle session/process group after autostart returns.
# BB must remain in its own session with the exact recorded app PID.
session_state="$fixture/session-survival"
mkdir "$session_state" "$fixture/forced-setsid"
cat > "$fixture/forced-setsid/setsid" <<'FORCED_SETSID'
#!/usr/bin/env bash
exec /usr/bin/setsid --fork "$@"
FORCED_SETSID
chmod 755 "$fixture/forced-setsid/setsid"
write_options 49286 49287 https://bb.example.test "$session_state"
HOME="$fixture/home" "$share/bin/bb-feature-bootstrap"
lifecycle_pid_file="$fixture/lifecycle.pid"
lifecycle_returned="$fixture/lifecycle-returned"
setsid bash -c '
  set -e
  printf "%s\n" "$$" > "$1"
  PATH="$2:$PATH" HOME="$3" "$4"
  : > "$5"
  sleep 30
' bb-lifecycle "$lifecycle_pid_file" "$fixture/forced-setsid" "$fixture/home" \
  "$share/bin/bb-feature-autostart" "$lifecycle_returned" &
lifecycle_job=$!
for _ in $(seq 1 400); do
  [ -e "$lifecycle_returned" ] && break
  kill -0 "$lifecycle_job" 2>/dev/null || { echo 'lifecycle exited before autostart returned' >&2; exit 1; }
  sleep .1
done
test -e "$lifecycle_returned"
lifecycle_pid="$(cat "$lifecycle_pid_file")"
session_pid="$(awk -F '\t' '$1=="PID"{print $2}' "$session_state/.bb-feature/launcher.tsv")"
session_command="$(tr '\000' ' ' < "/proc/$session_pid/cmdline")"
[[ "$session_command" == *"$share/npm/bin/bb-app"* ]]
[[ "$session_command" == *"--data-dir $session_state"* ]]
test "$(ps -o sid= -p "$session_pid" | tr -d ' ')" = "$session_pid"
test "$(ps -o sid= -p "$lifecycle_pid" | tr -d ' ')" = "$lifecycle_pid"
test "$session_pid" != "$lifecycle_pid"
kill -TERM -- "-$lifecycle_pid"
wait "$lifecycle_job" 2>/dev/null || true
for _ in $(seq 1 50); do kill -0 "$lifecycle_pid" 2>/dev/null || break; sleep .1; done
! kill -0 "$lifecycle_pid" 2>/dev/null
HOME="$fixture/home" "$share/bin/bb-feature-status"
test "$session_pid" = "$(awk -F '\t' '$1=="PID"{print $2}' "$session_state/.bb-feature/launcher.tsv")"

# Clean up only the recorded fixture process, with a bounded wait.
kill -TERM "$session_pid"
for _ in $(seq 1 100); do kill -0 "$session_pid" 2>/dev/null || break; sleep .1; done
! kill -0 "$session_pid" 2>/dev/null
rm "$session_state/.bb-feature/launcher.tsv"
echo 'BB survives lifecycle session cleanup with its real PID; cleanup is bounded'

# A status check that lands while autostart holds the lifecycle lock but has not
# yet recorded its launcher must wait for that start, not report "not ready".
# The fixture gates autostart after BB is listening and before the record is
# written (at the PID-handoff cleanup), so the race is hit every run.
gated_state="$fixture/gated-start"
start_gate="$fixture/start-gate"
mkdir "$gated_state" "$fixture/gated-rm"
cat > "$fixture/gated-rm/rm" <<'GATED_RM'
#!/usr/bin/env bash
case "$*" in *launcher-start.*) while [ -e "$BB_TEST_START_GATE" ]; do sleep .05; done;; esac
exec /bin/rm "$@"
GATED_RM
chmod 755 "$fixture/gated-rm/rm"
write_options 49986 49987 https://bb.example.test "$gated_state"
HOME="$fixture/home" "$share/bin/bb-feature-bootstrap"
touch "$start_gate"
PATH="$fixture/gated-rm:$PATH" BB_TEST_START_GATE="$start_gate" HOME="$fixture/home" "$share/bin/bb-feature-autostart" & gated=$!
for _ in $(seq 1 100); do
  curl --fail --silent --max-time 1 http://127.0.0.1:49986/health >/dev/null 2>&1 && break
  sleep .1
done
curl --fail --silent --max-time 1 http://127.0.0.1:49986/health >/dev/null
test ! -e "$gated_state/.bb-feature/launcher.tsv"
kill -0 "$gated"
HOME="$fixture/home" "$share/bin/bb-feature-status" & gated_status=$!
sleep 1
kill -0 "$gated_status" || { echo 'status returned while autostart was still recording its launcher' >&2; exit 1; }
test ! -e "$gated_state/.bb-feature/launcher.tsv"
rm "$start_gate"
wait "$gated"
wait "$gated_status"
gated_pid="$(awk -F '\t' '$1=="PID"{print $2}' "$gated_state/.bb-feature/launcher.tsv")"
kill -TERM "$gated_pid"
for _ in $(seq 1 100); do kill -0 "$gated_pid" 2>/dev/null || break; sleep .1; done
kill -0 "$gated_pid" 2>/dev/null && { echo 'gated fixture launcher did not exit' >&2; exit 1; }
rm "$gated_state/.bb-feature/launcher.tsv"
# With no launcher and no autostart holding the lock, status still fails fast.
started=$SECONDS
if timeout 5 env HOME="$fixture/home" "$share/bin/bb-feature-status"; then echo 'status accepted a missing launcher' >&2; exit 1; fi
test $((SECONDS - started)) -le 2
echo 'status waits for an in-progress autostart that has not recorded its launcher'

write_options 49386 49387 https://bb.example.test "$state"
HOME="$fixture/home" "$share/bin/bb-feature-bootstrap"
grep -F 'https://bb.example.test' "$state/config.json"
test "$(stat -c %a "$state")" = 700

# Concurrent starts must wait for a delayed daemon, not just HTTP health.
printf '4\n' > "$state/daemon-delay"
HOME="$fixture/home" "$share/bin/bb-feature-autostart" & first=$!
HOME="$fixture/home" "$share/bin/bb-feature-autostart" & second=$!
for _ in $(seq 1 30); do
  curl --fail --silent --max-time 1 http://127.0.0.1:49386/health >/dev/null 2>&1 && break
  sleep .1
done
curl --fail --silent --max-time 1 http://127.0.0.1:49386/health >/dev/null
kill -0 "$first" && kill -0 "$second" || { echo 'autostart returned before delayed daemon readiness' >&2; exit 1; }
HOME="$fixture/home" "$share/bin/bb-feature-status" & starting_status=$!
sleep .5
kill -0 "$starting_status" || { echo 'status returned before delayed daemon readiness' >&2; exit 1; }
wait "$first"; wait "$second"
wait "$starting_status"
pid="$(awk -F '\t' '$1=="PID"{print $2}' "$state/.bb-feature/launcher.tsv")"
kill -0 "$pid"
HOME="$fixture/home" "$share/bin/bb-feature-autostart"
test "$pid" = "$(awk -F '\t' '$1=="PID"{print $2}' "$state/.bb-feature/launcher.tsv")"
HOME="$fixture/home" "$share/bin/bb-feature-status"
echo 'delayed daemon startup waits for both services; concurrent starts converge'

# A status check retries a real first-request timeout, then succeeds without
# changing the recorded launcher. The production per-probe timeout is unchanged.
cp "$state/.bb-feature/launcher.tsv" "$fixture/launcher-before-status.tsv"
touch "$state/health-timeout-once"
started=$SECONDS
timeout 15 env HOME="$fixture/home" "$share/bin/bb-feature-status"
elapsed=$((SECONDS - started))
test ! -e "$state/health-timeout-once"
test "$elapsed" -ge 2 && test "$elapsed" -le 13
cmp "$fixture/launcher-before-status.tsv" "$state/.bb-feature/launcher.tsv"
kill -0 "$pid"
echo "status recovers from a first-probe timeout without restarting (${elapsed}s)"

assert_status_fails_boundedly() {
  local started=$SECONDS result elapsed
  set +e
  timeout 15 env HOME="$fixture/home" "$share/bin/bb-feature-status"
  result=$?
  set -e
  elapsed=$((SECONDS - started))
  test "$result" = 1 && test "$elapsed" -ge 7 && test "$elapsed" -le 13
  cmp "$fixture/launcher-before-status.tsv" "$state/.bb-feature/launcher.tsv"
  kill -0 "$pid"
  echo "status fails boundedly without stopping/replacing launcher (${elapsed}s)"
}

# Rechecking an owned launcher also waits for daemon recovery without replacing
# that launcher. Status must fail while either service is unavailable.
touch "$state/daemon-pause"
sleep .3
assert_status_fails_boundedly
HOME="$fixture/home" "$share/bin/bb-feature-autostart" & recovering=$!
sleep 1
kill -0 "$recovering" || { echo 'existing-launcher path returned before daemon recovery' >&2; exit 1; }
rm "$state/daemon-pause"
wait "$recovering"
test "$pid" = "$(awk -F '\t' '$1=="PID"{print $2}' "$state/.bb-feature/launcher.tsv")"
touch "$state/server-unhealthy"
assert_status_fails_boundedly
rm "$state/server-unhealthy"
HOME="$fixture/home" "$share/bin/bb-feature-status"
echo 'existing-launcher recovery and status require both services'

# A writable runtime record is never removed or used to kill anything.
chmod 666 "$state/.bb-feature/launcher.tsv"
if HOME="$fixture/home" "$share/bin/bb-feature-autostart"; then echo 'accepted writable runtime record' >&2; exit 1; fi
chmod 600 "$state/.bb-feature/launcher.tsv"

# A healthy HTTP server whose daemon never listens must fail in bounded time.
never_state="$fixture/never-daemon"
mkdir "$never_state"
touch "$never_state/daemon-never"
write_options 49886 49887 https://bb.example.test "$never_state"
started=$SECONDS
set +e
timeout 40 env HOME="$fixture/home" "$share/bin/bb-feature-autostart" >"$fixture/never.log" 2>&1
result=$?
set -e
elapsed=$((SECONDS - started))
test "$result" = 1 && test "$elapsed" -ge 29 && test "$elapsed" -le 36
grep -F 'BB server and host daemon did not become ready within 30 seconds' "$fixture/never.log"
test ! -e "$never_state/.bb-feature/launcher.tsv"
echo "never-listening daemon fails within the readiness budget (${elapsed}s)"

# Auto origin rejects partial Codespaces environment before launching.
write_options 49486 49487 auto "$fixture/missing-codespaces"
if HOME="$fixture/home" CODESPACE_NAME=demo "$share/bin/bb-feature-bootstrap"; then echo 'accepted incomplete Codespaces origin' >&2; exit 1; fi

# A healthy unrelated listener is reported as a conflict, not stopped.
python3 - 49586 >"$fixture/conflict.log" 2>&1 <<'PY' &
import http.server, socketserver, sys
class H(http.server.BaseHTTPRequestHandler):
 def do_GET(self): self.send_response(200); self.end_headers()
 def log_message(self, *a): pass
socketserver.TCPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
conflict=$!
sleep 1
write_options 49586 49587 http://127.0.0.1:49586 "$fixture/conflict-state"
if HOME="$fixture/home" "$share/bin/bb-feature-autostart"; then echo 'accepted unrelated listener' >&2; exit 1; fi
kill "$conflict" 2>/dev/null || true

# Persisted shell metacharacters are rejected before using the path.
write_options 49686 49687 auto "$fixture/a;touch no"
if HOME="$fixture/home" "$share/bin/bb-feature-bootstrap"; then echo 'accepted unsafe saved path' >&2; exit 1; fi
test ! -e "$fixture/no"

# A lexical ancestor symlink must be rejected before mkdir -p can create
# Feature state through it. (realpath alone would resolve this and miss it.)
mkdir "$fixture/real-parent"
ln -s "$fixture/real-parent" "$fixture/linked-parent"
write_options 49786 49787 auto "$fixture/linked-parent/nested-state"
if HOME="$fixture/home" "$share/bin/bb-feature-bootstrap"; then echo 'accepted data path with symlink ancestor' >&2; exit 1; fi
test ! -e "$fixture/real-parent/nested-state"
echo 'bb adversarial runtime lifecycle validation passed'
