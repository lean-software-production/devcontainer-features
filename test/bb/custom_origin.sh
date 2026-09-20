#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "explicit origin is persisted through bb-app config" bash -c "grep -F 'https://bb.example.test' '/tmp/bb custom state/config.json'"
check "custom standalone port is healthy" bash -c "curl --fail --silent http://127.0.0.1:48286/health | grep -q '\"ok\":true'"
# A 101 connection is persistent by design; time out only after its headers.
check "configured origin is accepted for websocket" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: https://bb.example.test' http://127.0.0.1:48286/ws | grep -q '101'"
# BB_APP_URL is additive: upstream buildLocalAppOrigins always retains the
# server's 127.0.0.1 and localhost origins. An external origin is not an
# exclusive allowlist, so test hostile/opaque origins as the security boundary.
# https://github.com/get-bb/bb/blob/e865697f56bea89f3413dd4cc7fae964850d20a0/packages/config/src/local-app-origins.ts
check "loopback origin remains accepted with an external app URL" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: http://127.0.0.1:48286' http://127.0.0.1:48286/ws | grep -q '101'"
for origin in https://attacker.invalid null; do
    for endpoint in /ws /ws/terminals/does-not-exist; do
        check "untrusted origin $origin is rejected on $endpoint" bash -c "timeout 5 curl --max-time 3 --silent --show-error --http1.1 -D - -o /dev/null -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Origin: $origin' http://127.0.0.1:48286$endpoint | grep -q '403'"
    done
done
reportResults
