#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

state='/tmp/bb feature state'
port=48186
origin="http://127.0.0.1:${port}"

check "standalone state is remote-user owned" bash -c "test \$(stat -c %u '$state') = \$(id -u) && test \$(stat -c %a '$state') = 700"
check "standalone server becomes healthy" bash -c "curl --fail --silent http://127.0.0.1:$port/health | grep -q '\"ok\":true'"
check "host daemon helper is listening only on its configured local port" bash -c "node -e \"const n=require('net').connect({host:'127.0.0.1',port:48187});n.once('connect',()=>process.exit(0));n.once('error',()=>process.exit(1));setTimeout(()=>process.exit(1),2000)\""
check "static UI is served" bash -c "curl --fail --silent http://127.0.0.1:$port/ | grep -qi '<!doctype html'"
check "public API responds without ambient BB variables" env -u BB_CLI -u BB_SERVER_URL -u BB_SERVER_HEADERS -u BB_DATA_DIR bash -c "curl --fail --silent http://127.0.0.1:$port/api/v1/projects | grep -q ."
# A successful WebSocket upgrade deliberately stays open. Bound curl so the
# test checks the handshake headers without waiting forever for a close frame.
check "same-origin realtime websocket upgrades" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: $origin' http://127.0.0.1:$port/ws | grep -q '101'"
check "foreign websocket origin is rejected" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: https://attacker.invalid' http://127.0.0.1:$port/ws | grep -q '403'"
check "foreign terminal websocket origin is rejected" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: https://attacker.invalid' http://127.0.0.1:$port/ws/terminals/does-not-exist | grep -q '403'"
check "autostart is idempotent" bash -c "before=\$(awk -F '\t' '\$1==\"PID\"{print \$2}' '$state/.bb-feature/launcher.tsv'); bb-feature-autostart; after=\$(awk -F '\t' '\$1==\"PID\"{print \$2}' '$state/.bb-feature/launcher.tsv'); test \"\$before\" = \"\$after\""
check "status reports the configured browser origin" bash -c "bb-feature-status | grep -F '$origin'"
reportResults
