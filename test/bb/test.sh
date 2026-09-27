#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "Feature-owned bb-app launcher is installed" bash -c "test -x /usr/local/share/bb/npm/bin/bb-app"
check "bb-app version is pinned by default" bash -c "node -e \"process.exit(require('/usr/local/share/bb/npm/lib/node_modules/bb-app/package.json').version === '0.43.4' ? 0 : 1)\""
check "reviewed native addons are usable" bash -c "node -e \"require('/usr/local/share/bb/npm/lib/node_modules/bb-app/node_modules/node-pty'); require('/usr/local/share/bb/npm/lib/node_modules/bb-app/node_modules/@parcel/watcher')\""
check "upstream BB notice is retained" bash -c "grep -q 'MIT License' /usr/local/share/bb/NOTICE"
check "public lifecycle helpers are installed" bash -c "command -v bb-feature-bootstrap && command -v bb-feature-autostart && command -v bb-feature-status"
check "BB CLI links target the Feature-owned package" bash -c '
    for command in bb bb-app bb-server bb-host-daemon; do
        target=$(readlink -f "/usr/local/bin/$command") || exit 1
        expected=$(readlink -f "/usr/local/share/bb/npm/bin/$command") || exit 1
        case "$target" in /usr/local/share/bb/npm/lib/node_modules/bb-app/*) ;; *) exit 1 ;; esac
        test "$target" = "$expected" && test -x "$target" || exit 1
    done
'
check "cli-mode bootstrap is a clean no-op" env -u BB_CLI -u BB_SERVER_URL -u BB_SERVER_HEADERS -u BB_DATA_DIR bash -c "bb-feature-bootstrap"
check "cli-mode autostart is a clean no-op" env -u BB_CLI -u BB_SERVER_URL -u BB_SERVER_HEADERS -u BB_DATA_DIR bash -c "bb-feature-autostart"
check "cli mode does not create default BB state" bash -c "test ! -e \$HOME/.bb/.bb-feature"
check "options are root-owned and not writable by others" bash -c "test \$(stat -c %u /usr/local/share/bb/options.tsv) = 0 && test \$((8#\$(stat -c %a /usr/local/share/bb/options.tsv) & 022)) = 0"
reportResults
