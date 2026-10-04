#!/usr/bin/env bash
# Machine mode without a learner's secrets: the container still starts, the
# hooks say what is missing, and nothing runs. (A connected machine needs a
# real hosted server; see src/bb/NOTES.md, "Machine mode".)
set -e
source dev-container-features-test-lib

clean() { env -u BB_CLI -u BB_SERVER_URL -u BB_SERVER_HEADERS -u BB_DATA_DIR -u BB_MACHINE_SERVER_URL -u BB_MACHINE_ACCESS_CLIENT_ID -u BB_MACHINE_ACCESS_CLIENT_SECRET "$@"; }

check "bb-app 0.45.0 is installed" bash -c "node -e \"process.exit(require('/usr/local/share/bb/npm/lib/node_modules/bb-app/package.json').version === '0.45.0' ? 0 : 1)\""
check "the machine helper is installed" test -x /usr/local/share/bb/bin/bb-feature-machine
check "bootstrap prepares ~/.bb-machine, mode 0700" clean bash -c 'bb-feature-bootstrap && test "$(stat -c %a "$HOME/.bb-machine")" = 700'
check "without a server URL, autostart says what to set and exits 0" clean bash -c 'bb-feature-autostart | grep -q BB_MACHINE_SERVER_URL'
check "and nothing is running" clean bash -c '! bb-feature-status && ! pgrep -f "[b]b-app host-daemon"'
check "an http server URL is refused" clean bash -c 'BB_MACHINE_SERVER_URL=http://example.test bb-feature-autostart 2>&1 | grep -q "https origin"'
check "half an Access token is refused before anything starts" clean bash -c 'out=$(BB_MACHINE_SERVER_URL=https://example.invalid BB_MACHINE_ACCESS_CLIENT_ID=x bb-feature-autostart 2>&1 || true); echo "$out" | grep -q "set both" && ! pgrep -f "[b]b-app host-daemon"'
check "a token never lands in a world-readable file" clean bash -c 'BB_MACHINE_SERVER_URL=https://example.invalid BB_MACHINE_ACCESS_CLIENT_ID=id.access BB_MACHINE_ACCESS_CLIENT_SECRET=s3cret bb-feature-autostart >/dev/null 2>&1 || true; ! grep -rl s3cret "$HOME" --include="*.log" 2>/dev/null | grep -q . && test "$(stat -c %a "$HOME/.bb-machine/.bb-feature/machine.env")" = 600'
reportResults
