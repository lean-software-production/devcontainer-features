#!/usr/bin/env bash
# Runs without an image build so CI can verify rejection paths that cannot be
# represented as successful Feature scenarios. It never invokes bb-app.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/src/bb/install.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect_reject() {
    local label="$1"; shift
    if env -i PATH="$PATH" HOME="$tmp" "$@" bash "$installer" >"$tmp/out" 2>&1; then
        echo "expected rejection: $label" >&2
        exit 1
    fi
}

# Validation happens before package/OS installation, so these tests cannot
# download or execute BB and are safe on the CI runner.
expect_reject 'shell injection in dataDir' DATADIR='/tmp/a;touch pwned'
expect_reject 'shell injection in appUrl' APPURL='https://x.invalid/$(id)'
expect_reject 'appUrl with a path' APPURL='https://x.invalid/not-an-origin'
expect_reject 'invalid port' SERVERPORT=not-a-port
expect_reject 'colliding ports' SERVERPORT=48886 HOSTDAEMONPORT=48886
expect_reject 'bad mode' MODE=server
expect_reject 'unvalidated version' VERSION='0.43.3;id'
test ! -e "$tmp/pwned"

# This direct helper check remains runnable without the root-owned Feature
# harness; the full lifecycle test repeats it as root in the feature runner.
mkdir "$tmp/real-state-parent"
ln -s "$tmp/real-state-parent" "$tmp/state-parent-link"
if bash -c ". '$repo_root/src/bb/bin/bb-feature-common.sh'; bb_feature_no_symlink_ancestors '$tmp/state-parent-link/nested'"; then
    echo 'accepted data path with symlink ancestor' >&2
    exit 1
fi
echo 'bb adversarial option validation passed'
