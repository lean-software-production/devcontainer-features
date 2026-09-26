#!/usr/bin/env bash
# Runs without an image build so CI can verify rejection paths that cannot be
# represented as successful Feature scenarios. Option validation happens before
# the installer touches the system, and the runner has no bb Feature, so even an
# accepted option set stops at the bb prerequisite without installing anything.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
installer="$repo_root/src/tutor/install.sh"
[ ! -e /usr/local/share/bb ] || { echo "refusing to run: a bb Feature is installed here, so accepted options would really install" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_installer() { env -i PATH="$PATH" HOME="$tmp" "$@" bash "$installer" >"$tmp/out" 2>&1; }

expect_reject() {
    local label="$1" message="$2"; shift 2
    if run_installer "$@"; then
        echo "expected rejection: $label" >&2
        exit 1
    fi
    grep -qF -- "$message" "$tmp/out" || { echo "rejected for the wrong reason: $label" >&2; cat "$tmp/out" >&2; exit 1; }
}

expect_reject 'relative course' 'course must be' COURSE=tutorial
expect_reject 'course is the root' 'course must be' COURSE=/
expect_reject 'shell injection in course' 'course must be' COURSE='/tmp/a;touch pwned'
expect_reject 'quote in course' 'course must be' COURSE='/tmp/a"b'
expect_reject 'dot traversal in course' 'course must be' COURSE=/workspaces/../etc
# shellcheck disable=SC2016 # the literal text is the attack
expect_reject 'command substitution in factory' 'factory must be' FACTORY='/tmp/$(id)'
expect_reject 'relative factory' 'factory must be' FACTORY=my-factory
expect_reject 'factory equals course' 'must be different' COURSE=/workspaces/x FACTORY=/workspaces/x/
expect_reject 'relative starter' 'starter must be' STARTER=capstone-project-starter
# shellcheck disable=SC2016 # the literal text is the attack
expect_reject 'command substitution in starter' 'starter must be' STARTER='/tmp/$(id)'
expect_reject 'starter equals course' 'starter and course must be different' COURSE=/workspaces/x STARTER=/workspaces/x/
expect_reject 'starterRepo without starter' 'starterRepo needs a starter' STARTERREPO=https://github.com/lean-software-production/capstone-project-starter.git
expect_reject 'plain http starterRepo' 'starterRepo must be' STARTER=/workspaces/s STARTERREPO=http://github.com/lean-software-production/capstone-project-starter.git
expect_reject 'option injection in starterRepo' 'starterRepo must be' STARTER=/workspaces/s STARTERREPO='--upload-pack=touch pwned'
expect_reject 'credentials in starterRepo' 'no credentials' STARTER=/workspaces/s STARTERREPO=https://user:secret@github.com/x/y.git
expect_reject 'bad selectOutline' 'selectOutline must be' SELECTOUTLINE=yes
expect_reject 'ssh courseRepo' 'courseRepo must be' COURSEREPO=git@github.com:lean-software-production/tutorial.git
expect_reject 'plain http courseRepo' 'courseRepo must be' COURSEREPO=http://github.com/lean-software-production/tutorial.git
expect_reject 'option injection in courseRepo' 'courseRepo must be' COURSEREPO='--upload-pack=touch pwned'
expect_reject 'credentials in courseRepo' 'no credentials' COURSEREPO=https://user:secret@github.com/x/y.git
expect_reject 'shell injection in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations;touch pwned'
expect_reject 'upper case in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS=Automations
expect_reject 'empty item in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations,,workflows'
expect_reject 'space in disablePlugins' 'disablePlugins must be' DISABLEPLUGINS='automations, workflows'
expect_reject 'shell injection in theme' 'theme must be' THEME='plugin:tutor:paper;touch pwned'
expect_reject 'space in theme' 'theme must be' THEME='my theme'
test ! -e "$tmp/pwned"
test ! -e pwned

# Valid options, including an empty courseRepo and a starter, pass validation and stop only
# at the missing bb Feature.
expect_reject 'defaults without the bb Feature' 'the bb Feature must be installed first'
expect_reject 'explicit options without the bb Feature' 'the bb Feature must be installed first' \
    COURSE=/workspaces/course/ COURSEREPO= FACTORY=/workspaces/my-factory SELECTOUTLINE=false DISABLEPLUGINS= THEME=
expect_reject 'the starter layout without the bb Feature' 'the bb Feature must be installed first' \
    STARTER=/workspaces/capstone-project-starter/ STARTERREPO=https://github.com/lean-software-production/capstone-project-starter.git \
    FACTORY=/workspaces/capstone-project-starter/tetris/.factory
expect_reject 'plugin list and theme without the bb Feature' 'the bb Feature must be installed first' \
    DISABLEPLUGINS=automations,tutor,provider-codex THEME=nord
echo 'tutor adversarial option validation passed'
